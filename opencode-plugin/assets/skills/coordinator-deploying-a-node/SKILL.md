---
name: coordinator-deploying-a-node
description: "Use when deploying a build to a single node, migrating or not — deploying a build, schema-migrating deploy, pro-bundle install plus service restart on a node, roll out a build to a node, ship to a node, single-node canary. Loads the deploy runbook — verifying the artifact actually CONTAINS the fix, install-before-restart ordering, verify-by-effect, and preventing store corruption on migration."
---

# Coordinator: Deploying a Build to a Single Node — migrating or not

> This runbook covers EVERY deploy to a single node, migrating or not. Most sections apply to every deploy; only migration-weight and store-corruption specifics are bump-only.

## 0. Pull-current first (ff-only)

The absolute first action before anything else: fetch the control-plane repository and fast-forward to the orchestrator's pin.

- Read the project's deployment adapter inside `.thrum/config.json` (`fleet.deployment`; reference at the deployment-adapter reference) to obtain `preflight.pull_command` and `preflight.pin_command`.
- Run `preflight.pull_command` (must be ff-only; if not fast-forwardable, STOP and surface — never blind-merge in the shared tree).
- Verify the delivered artifact actually CONTAINS the fix at the pinned SHA (adapter `artifact.commit_file` sidecar).

This ensures the node's coordinator reasons from a checkout that is actually current before evaluating backup, install, or migration.

> Example — Thrum project: pull via `git fetch origin && git merge --ff-only origin/<branch>` before any backup or install.

## 1. Who executes — resolve the node's local coordinator (via adapter identity)

The node's own coordinator drives the deploy locally on its own host. Never drive a node's build/install/restart from another host.

- Resolve WHO via `topology.identity_resolution` (adapter `fleet.deployment.thrum.topology.identity_resolution` or `fleet.deployment.products.<id>.topology`) — a `daemon_id` join plus hostname and absence of `.thrum/redirect`, never by agent name or worktree name.
- When connected-repo daemons share a host, respect the adapter-defined restart order within that host.

If the target node has no working coordinator, state why explicitly before using any fallback.

## 2. Back up before touching anything (via adapter backup command + sizing formula)

- Run the project's backup command (`fleet.deployment.thrum.backup.command` or `fleet.deployment.products.<id>.backup.command`) and verify per `backup.verify`.
- Size BEFORE you run it on a bloated node: apply the adapter's `backup.sizing_formula` (`free_at_completion = free_now - zip(stale current/) + size(stale current/) - size(live lane)`) — the stale `current/` is removed before the fresh export, so peak is not double-count. Retention runs last and does not bound the peak.
- On failure, roll back via `backup.restore_command`; never delete the store.

> Example — Thrum project: backup via `thrum backup`, sized per the formula above, verified with `sqlite3 ?mode=ro&immutable=1` read.

## 3. Storage access — through the engine or control-plane CLI, never file-bypass

Access the state store only through the engine or the control-plane CLI in read-only mode. Never bypass the storage engine's file ownership.

- Via: `storage_access.via` (e.g., CLI or `?mode=ro`).
- Forbidden: `storage_access.forbidden` (e.g., hand-copy of live `-wal`/`-shm`, concurrent `.backup` on live store).
- A bare read-write open can fire a checkpoint that truncates the write log out from under live readers → sustained corruption. Always use `?mode=ro` where applicable.

If the project has no WAL/SHM, this section is N/A — skip and note.

## 4. Never wrap service start/restart in a blind timeout

Run the project's service restart command (`fleet.deployment.thrum.service.restart_command` or product equivalent) without a blind timeout wrapper. A timeout that kills a migrating restart mid-migration manufactures a half-migrated store.

- Adapter flag `service.never_timeout` is true.
- Signal-window rules are adapter data: `migration.signal_rules` (`SIGQUIT` fatal-always, `SIGUSR1` fatal-before-socket). Respect them — do not send fatal signals in the forbidden window.

> Example — Thrum project: restart via `thrum daemon restart`, never wrapped in `timeout`; mac path via `scripts/mac-daemon-restart-via-cron.sh`.

## 5. Install from the delivered artifact (never rebuild on the node)

Install from the identical bundle the orchestrator built, delivered to `artifact.distribution.drop_path`.

- Verify BEFORE unpack that the delivered bundle's version/checksum/commit sidecar equals the orchestrator's pin (adapter `artifact.checksum`, `artifact.version_file`, `artifact.commit_file`).
- Run `install.command` (from adapter). The node does not compile, sign, or rebuild — it installs.
- Collect BEFORE readings (current version, state counters, checkpoint counts, health probes) before the install.

> Example — Thrum project: install from the adapter's `artifact.distribution.drop_path` via the adapter's `install.command`.

## 6. Measure from the running process, never the checkout

Read version/state from the running service, not from the filesystem checkout.

- Verify via `install.verify_by_effect` probes: version equals pin, NEW PID, service status reports pin, sidecar equals pin.
- Do not trust installer exit 0 alone.

## 7. Migrate via service restart — verify by effect

Migration is performed by restarting the service after install; the service's own boot migration does the schema/data move.

- Calibrate weight via `migration.weight_calibration` (heavy bulk-export vs light add-column) — do not assume a fixed duration.
- Known signatures that require a cold-restart recovery: `migration.sigbus_signatures` (e.g., WAL-index recover signatures) and `migration.on_sigbus`.
- Observe that the restarted service reports the new version/state and that health probes have converged (adapter `health.probes`, `health.convergence_wait`).

## 8. Verify post-migration (liveness, health probes, checkpoint counts, agent liveness)

Run adapter `health.probes` and compare BEFORE/AFTER:

- Service alive and reporting pin.
- State counters converged per `health.convergence_wait` (mechanism-derived, e.g., `3m`).
- Crash log empty, expected agents live.

For tandem daemons that share a host or depend on each other, verify the coordinated set per adapter.

## 8a. Re-render configuration/templates if the build changes them

If the build carries template or role changes, re-render between install and restart:

- Commands: `templates.refresh_command` and `templates.deploy_command`.
- Order: `templates.order` (`refresh→deploy` between `install.sh` and daemon restart).
- Verify by effect (render output, then service restart).

> Example — Thrum project: `thrum roles refresh` then `thrum roles deploy` between install and restart.

## 8b. Plugin/skill refresh if the deploy carries skill changes

If the bundle carries skill/plugin changes, refresh the plugin cache:

- Refresh driver: `plugin.refresh` (version bump required — cache keyed by version).
- Manifests: `plugin.manifests` (all skill-carrying manifests bumped in the same commit as the new skills).

Do not hand-edit generated marketplace manifests.

## 8c. Reconcile registry/phase after restart

Re-verify the daemon registry and agent phases after restart (adapter `health.probes` includes phase reconciliation). Confirm the pinned version is durable across a clean cold-boot probe where applicable.

## Red flags — STOP

- Pull not ff-only.
- Backup skipped or undersized.
- Storage accessed via forbidden path (`storage_access.forbidden`).
- Restart wrapped in a blind timeout or killed with `SIGQUIT`/`SIGUSR1` in a fatal window (`migration.signal_rules`).
- Install rebuilt locally instead of from the delivered artifact.
- Post-migration health not verified by observed effect.
- Template re-render skipped when the build changed templates (`templates.order` violated).
