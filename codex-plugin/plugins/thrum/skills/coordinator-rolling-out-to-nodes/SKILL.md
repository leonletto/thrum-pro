---
name: coordinator-rolling-out-to-nodes
description:
  "Use when rolling a build across all nodes — fleet deploy, rolling the nodes,
  deploy everywhere, ship to every node, canary then the rest, promote the
  canary, staged rollout, deploying after a merge batch. Orchestrates the staged
  order and the promotion gate between stages, and delegates each node to the
  coordinator-deploying-a-node runbook. Load this BEFORE dispatching any node."
# source: claude-plugin/skills/coordinator-rolling-out-to-nodes/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator: Rolling Out a Build Across All Nodes — staged order, canary, promotion gate

> This skill is the ORCHESTRATION layer. It does not replace
> `coordinator-deploying-a-node` — it calls it, once per node.

### 0. Universal invariants (read first — these outrank everything below)

These hold for every deployment regardless of project or topology. The adapter
supplies _how_, these define _what must be true_.

1. **Build once; distribute identical bytes.** One pinned immutable artifact
   (SHA/version/checksum triple) is built once at one SHA on the build host;
   every node installs from that same artifact. No node re-derives it. Pin exact
   SHA, never tip. Adapter: `fleet.deployment.thrum.artifact` or
   `fleet.deployment.products.<id>.artifact`.
2. **Target-local mutation.** The node-local coordinator performs the mutation
   (install/migrate/restart) locally on its own host. Never drive a node's
   build/install/restart from another host. The orchestrator dispatches and
   gates; the node executes.
3. **Immutable identifier + checksum.** Artifact is identified by SHA +
   version + checksum; verify BEFORE install that the delivered bundle is the
   one the orchestrator built. Adapter: `artifact.checksum`,
   `artifact.version_file`, `artifact.commit_file`.
4. **Canary evidence does not transfer.** A canary pass proves the _build_ is
   sound; it does not prove any other node's _state_ is sound. Every node takes
   its own BEFORE readings.
5. **Verify by observed effect, never exit code.** Install/restart success is
   proven by post-mutation observation (version equals pin, NEW PID, service
   status reports pin, migration moved), not by installer exit 0. Adapter:
   `install.verify_by_effect`, `health.probes`.
6. **Capture before/after.** For every node, capture BEFORE state (current
   version/state, health counters) before mutation and AFTER state after;
   compare.
7. **Account for every target.** Roster completeness: enumerate topology from
   config, disposition each node (rolled on pin / deferred with owner sign-off +
   notify local coordinator), and never normalize unmeasured rows.

Additional parameterized invariants (skill-owned, adapter-valued):

- Pull-current first (ff-only) before reasoning about state. Adapter:
  `preflight.pull_command`.
- Backup before touching anything; sizing via adapter formula. Adapter:
  `backup.command`, `backup.sizing_formula`.
- Never bypass the storage engine's file ownership. Adapter:
  `storage_access.via`, `storage_access.forbidden`.
- Install-before-restart ordering; re-render between install and restart.
  Adapter: `templates.order`.
- Convergence wait from mechanism, not impatience. Adapter:
  `health.convergence_wait`.

### 1. Enumerate topology (from adapter — never hard-code)

Read the project's deployment adapter inside `.thrum/config.json`
(`fleet.deployment`; human-readable reference at the deployment-adapter
reference). Never hard-code topology or commands in the dispatch or in this
skill — read them from that single source.

- For Thrum fleet plus connected daemons: `fleet.deployment.thrum.topology`
  (`canary`, `waves`, `excluded`, `connected_daemons`, `identity_resolution`).
- For a customer product `<id>`: `fleet.deployment.products.<id>.topology` (same
  shape, per-product `canary`/`nodes`/`waves`).

Resolve each node's `daemon_id` / `ssh_alias` / `coordinator` via the adapter's
`identity_resolution` method (daemon_id join, not name). If topology is empty,
STOP — do not invent nodes.

> Example — Thrum project: topology canary and waves are defined in
> `topology.canary` / `topology.waves` (seven boxes, one excluded), connected
> daemons per `topology.connected_daemons`. Build host and build command are
> adapter values, not skill literals.

### 2. Pin the artifact (build once at SHA/version/checksum)

Derive the immutable pin on the build host (adapter `artifact.build_host`):
current `HEAD` SHA, version, and checksum. When multiple related artifacts
(e.g., core plus connected-repo bundles) are involved, pin each immutably and
distribute the same set to every relevant node. Announce the pin in the dispatch
so every node can verify it.

Artifact identity lives in `artifact.output`, `artifact.version_file`,
`artifact.commit_file`, `artifact.checksum`. Never use a floating tag like tip;
always the pinned SHA.

### 3. Preflight (control-plane current, forward-only, backup sizing via adapter)

- Verify control-plane checkout is current: `preflight.pull_command` (must be
  ff-only; if not fast-forwardable, STOP and surface).
- Forward-only check per node: `preflight.forward_only_check` — prove the pin is
  an ancestor of the node's current SHA (plus a control that must FAIL, e.g., an
  invented SHA, to prove the check discriminates).
- Backup sizing via adapter: `backup.sizing_formula` — compute
  `free_at_completion` per the formula before running `backup.command`; if the
  projected peak exceeds the safe threshold, STOP and escalate.

### 4. Build once → distribute identical artifact (mechanism via adapter)

Build once per artifact on its `artifact.build_host` via
`artifact.build_command` → verify the produced bundle's version/checksum/commit
sidecar → distribute the identical bytes to every node's inbound drop path
(`artifact.distribution.drop_path`) via the adapter's
`artifact.distribution.mechanisms` (e.g., drop-folder or copy). No node
re-derives or rebuilds. Verify BEFORE unpack that the delivered bundle matches
the pin.

> Example — Thrum project: build once via the adapter's `artifact.build_command`
> on the adapter's `artifact.build_host`, distribute via the adapter's
> `artifact.distribution.mechanisms` to `artifact.distribution.drop_path`,
> bundle carries sidecars verified per adapter.

### 5. The staged order — canary, waves, prepare-and-hold, promotion gate

- **Canary first, alone.** One node (adapter `topology.canary`) rolls first. Its
  health must be observed green before any wave proceeds.
- **Waves with coordinated dependency/order/rollback.** Subsequent waves follow
  `topology.waves`. When related daemons share ordering (e.g., connected-repo
  daemons that must restart together), respect the adapter-defined dependency
  and restart order; a failure in one dependent daemon triggers coordinated
  rollback per adapter `rollback` / `backup.restore_command`.
- **Prepare-and-hold + release BY NAME.** If the mechanism supports it, prepare
  all nodes in a wave (acquire + verify artifact, take BEFORE snapshot, but do
  not restart) then release by explicit node name, not by broadcast.
- **Promotion gate.** After each stage, verify by observed effect on that node
  (see node skill) before promoting. On no-go, halt the rollout and roll back
  the affected node(s) per adapter.

### 6. Dispatching a node — what the message must carry

Dispatch each node to its own local coordinator (resolved via
`identity_resolution`), never via remote shell for the mutation itself. The
dispatch message must carry:

- Pinned artifact identifier (SHA/version/checksum) and drop-path location.
- Which adapter section to use (`fleet.deployment.thrum` vs
  `fleet.deployment.products.<id>`).
- Expected pin for verification and the BEFORE-snapshot request.
- Hold/release semantics if using prepare-and-hold.

The node's local runbook is `coordinator-deploying-a-node` — reference that
skill by name in the dispatch.

### 7. After the last node — roster completeness, phase reconciliation, test gate

- Enumerate the topology again from the same adapter source and disposition
  every entry (rolled on pin / deferred with owner sign-off + notify local
  coordinator). Missing or unmeasured rows are not normalized.
- Reconcile registry/phase: verify every daemon reports the pin (adapter
  `health.probes` + `install.verify_by_effect`), and that agent phases have
  converged.
- Run the project's gate that is appropriate for the change (e.g., `make gate`
  or equivalent) before declaring success.

### 8. Holds and red flags

- If `fleet.deployment` is absent or `fleet.deployment.products` and
  `fleet.deployment.thrum` are both empty, STOP — no topology is defined.
- If the control-plane pull is not fast-forwardable, STOP.
- If `fleet.deployment.thrum.products` exists (vestigial), STOP — products live
  only at `fleet.deployment.products`.
- If a node reports success by exit code alone without observed-effect
  verification, treat as not-verified.
- Never wrap a service restart in a blind timeout on the node (see node skill
  `service.never_timeout` and `migration.signal_rules`).
