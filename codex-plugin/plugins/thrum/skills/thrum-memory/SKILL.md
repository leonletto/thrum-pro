---
name: thrum-memory
description: "Use when capturing or querying structured memories (session summaries, architectural decisions, restart snapshots, agent rules) via the thrum memory CLI. Loads decision flowchart, kind taxonomy, default-safe behaviors, and pointers to advanced sub-skills."
# source: claude-plugin/skills/thrum-memory/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## thrum memory — capture and query structured memories

### When to use thrum memory vs. other stores

Did you just learn something that future-you should respect? YES →
`thrum memory create` (decide kind below) NO ↓

Is this transient task state (in-progress work, current session context)? YES →
`bd update` / `bd comments` (per-task notes) NO ↓

Is this long-form project narrative (architecture decisions, release status)?
YES → memory of kind `arch_decision` or `session_summary` (the integration
brainstorm will wire these into prime-assembly later) NO ↓

Is this code documentation (CLAUDE.md, READMEs, in-file comments)? YES → edit
the file directly; memory is for structured records, not docs.

### Kind taxonomy at a glance

- `session_summary` — what shipped in a session (replaces ad-hoc session notes)
- `arch_decision` — long-lived architectural decision; can be superseded later
- `current_state` — point-in-time state snapshot; expires fast
- `epic_status` — one row of "Open Epics / Active Work"
- `worktree_status` — one worktree-table row; expires per session
- `stable_infra` — long-lived infrastructure entry
- `resume_snapshot` — per-agent restart blob (scope=agent)
- `agent_rule` — rule/preference for future sessions (scope=role or
  scope=project)
- `comment` — comment on a parent memory (`child_of: <parent-id>`)

### Top operations (the 80% case)

Create with all three zoom levels (recommended; warns via MEM-010 otherwise):

```bash
thrum memory create --kind arch_decision \
  --title "Tailscale-only sync" \
  --oneline "Removed git a-sync; Tailscale peering is sole sync mechanism" \
  --short @short.md --full @full.md \
  --tag substrate,sync
```

`--short`/`--full` carry real prose — compose via heredoc or file, never
double-quoted inline; see your role preamble's 🔴 PROSE INTO A COMMAND rule.

Search by tag + kind, default limit 10:

```bash
thrum memory search --tag substrate --kind arch_decision
```

Show a single memory by ID:

```bash
thrum memory show thrum-mem-01HQXZP3V8K2N7M0YJWQ8R5T6F
```

Edit a single field (other zoom levels stay intact; only changed-zoom embeddings
re-queue):

```bash
thrum memory edit <id> --short @newshort.md
thrum memory edit <id> --add-tag v0.11 --rm-tag draft
```

Link an edge:

```bash
thrum memory link <new-id> supersedes <old-id>
thrum memory link <child-id> child_of <parent-id>
```

### Default-safe behaviors

- `--limit 10` by default for search (memory body_full is 5-50× larger than
  typical messages; bounded context pollution). `--limit 25` or higher is a
  one-flag opt-in for deeper exploration.
- `status=active` default filter (use `--status all` to include
  superseded/purged).
- **Scope is an ASSEMBLY filter** (NOT visibility/access control) —
  `memory.search` returns everything matching your predicates regardless of
  scope unless `--scope` is explicitly passed. Scope only affects which memories
  the (deferred) default assembler folds into an agent's prime context.

### Feature-scoped queries — use tags, not scope

Scope is closed (`project / agent / role`). For "feature-scoped" filtering
(e.g., "show me memories about the watcher-substrate feature"), use the
`feature-<name>` tag-naming convention:

```bash
thrum memory create --kind session_summary --tag feature-watcher-substrate,substrate ...
thrum memory search --tag feature-watcher-substrate --limit 10
thrum memory search --tag substrate --kind arch_decision  # one tag per query; for OR, run one search per tag
```

Convention only — no code enforces the `feature-` prefix, but discoverability
across agents/sessions depends on consistency.

### When you need more

- For RAG / `--near` queries / complex predicates / hint code interpretation:
  load the `memory-search-advanced` skill
- For edges, hierarchy, supersede semantics, comments-as-memories: load the
  `memory-curate` skill
- For audit history, undelete, hard-delete confirmation flow: load the
  `memory-audit-recover` skill

### First-time setup (configuration)

Embedding adapter is opt-in. Default config disables RAG; full-text search
(`--grep`) works without it. To enable RAG:

```bash
thrum config set llm.embedding.enabled true
thrum config set llm.embedding.provider ollama
thrum config set llm.embedding.base_url http://localhost:11434
thrum config set llm.embedding.model "granite-embedding:30m-english"
```

For non-English projects use `granite-embedding-multilingual-97m` instead.

`id_prefix` for memory IDs is auto-derived from your repo (git remote URL →
main-worktree basename → CWD basename, with normalization). To override:

```bash
thrum config set id_prefix "my-repo"
```

Rate limit and backfill knobs live under `embedding.max_per_minute` (default 60)
and `embedding.backfill_on_boot` (default true).
