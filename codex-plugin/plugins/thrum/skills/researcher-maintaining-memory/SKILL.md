---
name: researcher-maintaining-memory
description: "Use after completing research, when updating research memory, when verifying entries, or when working with the research index. Loads researcher-specific discipline — the index file structure, cite-stamp protocol, staleness check via git diff, namespace conventions. References common memory skills for write/read/maintain basics."
# source: claude-plugin/skills/researcher-maintaining-memory/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Researcher memory discipline

You are the researcher. You write research findings, role-rules, and curate the
project-local research index. Common memory operations (write command shape,
body conventions, lookup patterns, edit/delete protocol) live in the common
memory skills — invoke them when you need the basics. THIS skill carries
researcher-specific extensions only.

### When to invoke the commons

| Situation                                                                         | Skill to invoke           |
| --------------------------------------------------------------------------------- | ------------------------- |
| Drafting a new research note or role-rule                                         | `memory-write-discipline` |
| Loading role-rules at session start, finding a topic, looking up a specific entry | `memory-read-discipline`  |
| Editing, deleting, or superseding an entry; reviewing history                     | `memory-maintenance`      |

### The research index file

You curate **one hand-written artifact**: `.thrum/context/research.md` — a thin
index over the topics + open questions in this repo's research landscape.

**Canonical sections (required minimum):**

#### Repo Map

Your mental model of code-area boundaries — which packages do what, which files
are gateways into a subsystem, which conventions live where. This is researcher
synthesis that does NOT fit a memory-entry shape.

Example:

```text
- internal/daemon/        — daemon server (RPC handlers, websocket, unix socket)
- internal/daemon/rpc/    — RPC handler files (one per logical surface)
- internal/sync/          — Tailscale-based sync across clones
- internal/memory/        — v0.11 memory substrate (model, projection, embed)
- ui/packages/web-app/    — React SPA (single page; routing in components/)
```

#### Open Questions

> `thrum queue` now supersedes this free-text list for tracking open investigation threads (see thrum-og7pq / the researcher role's Task Tracking delta) — keep entries here only for historical context.

Researcher TODOs / things-to-investigate that haven't been resolved into
findings yet. Each line ≤120 chars; cite a file area or epic if relevant.

Example:

```text
- Is the embedding adapter wired post-rzp5.4? (check internal/memory/embed/adapter_ollama.go)
- thrum-puhr.9 monitor reliability follow-up still has 4 child bugs open
- Open: does --scope role on memory.create auto-infer the role, or does it require explicit value?
```

**Researcher-extensible sections (optional):** Beyond Repo Map + Open Questions,
you may add other sections that fit your workflow — e.g., a "Pending
Verifications" list, a "Cross-Repo Notes" section, a debugging-log scratchpad.
Frame the file as YOUR working artifact; don't constrain it to a fixed schema.

**What does NOT belong in the index:** A "Tracked Topics" mirror of memory
entries. The CLI owns enumeration:

```bash
thrum memory list --kind research_note --scope role     # the live, drift-free topic list
```

Use this instead of maintaining a parallel index of research notes in the
markdown file.

### Verification-stamp footer for research notes

Every research note (`kind: research_note`) ends with a Verified-stamp footer:

```text
Verified: YYYY-MM-DD @ <commit-sha>
```

The SHA is `git rev-parse HEAD` at verification time. This stamp enables
structural staleness review (next section).

When authoring a new research note via `thrum memory create`, include the stamp
at the bottom of `--full` body content. When re-verifying an existing note, edit
the entry to update the stamp:

```bash
cat > /tmp/memory-verify-body.md <<EOF
<verified body with updated 'Verified: ... @ <new-sha>' footer>
EOF
thrum memory edit <id> --full "@/tmp/memory-verify-body.md"
```

### Staleness check via git diff

For research notes that cite specific files, structural staleness review filters
the cited paths against changes since the last Verified-stamp. Pulling the note
follows the shared 3-step zoom escalation (`memory-read-discipline`): triage
short before paying for the full body.

```bash
# 1/2. Triage — confirm this is the right entry before pulling full content
thrum memory show <id> --zoom short

# 3. Fetch full body only once confirmed
thrum memory show <id> --format json --zoom full | jq -r '.body_full' > /tmp/note.txt

# Extract the Verified SHA
STAMP_SHA=$(grep -oE 'Verified: [0-9]{4}-[0-9]{2}-[0-9]{2} @ ([a-f0-9]+)' /tmp/note.txt | awk '{print $NF}')

# Extract cited paths (rough — depends on how your note cites)
CITED=$(grep -oE '[a-zA-Z_/-]+\.go|[a-zA-Z_/-]+\.md' /tmp/note.txt | sort -u)

# Diff cited paths since the stamp
git diff --name-only "$STAMP_SHA" HEAD -- $CITED
# If any output: paths have changed; re-verify the note before relying on it.
```

A non-empty diff signals possible staleness. Re-read the note's claims against
the changed code; either update + re-stamp (the note's claims still hold) or
amend / supersede the note (the claims have drifted).

### Namespace conventions for research_note entries

When authoring research notes, use `--tag <slug>` where `<slug>` is kebab-case
keywords describing the topic. Per D3 / D4 of the brainstorm, the title is
free-form prose; the slug-style handle lives in tags.

**User captures:** `--tag <slug>` (just the slug; no prefix needed).

**Module installs (forward-compatibility — module tooling is not in v1, but the
segment is reserved):** `--tag mod-<module-name> --tag <slug>` to avoid
clobbering user-authored entries with the same slug.

The legacy `research-<slug>` and `research-mod-<module>-<slug>` bd-key
conventions are retired. Migrated entries carry the original bd-key as title
(per rzp5.4 utility convention) + `--tag migrated-from-bd:<bd-key>` as the
rollback handle.

### Role-rule writes (researcher-specific)

When the user corrects your behavior mid-session, capture a researcher-rule:

```bash
cat > /tmp/role-rule-body.md <<'EOF'
<rule>

Why: <reason>
How to apply: <when/where>
EOF
thrum memory create --kind agent_rule --scope role \
  --title "<short rule prose>" \
  --oneline "<rule one-liner>" \
  --short "@/tmp/role-rule-body.md" \
  --tag <slug>
```

`--short`/`--full` carry real prose — compose via heredoc or file, never
double-quoted inline; see your role preamble's 🔴 PROSE INTO A COMMAND rule.

This is the SAME pattern as coordinator/implementer role-rule writes — see
`memory-write-discipline` for the canonical shape.

### Removal protocol

To retire a research note:

```bash
thrum memory delete <id>
```

(See `memory-maintenance` for hard-purge semantics if needed.) If the deleted
note had its slug or topic referenced in your `.thrum/context/research.md` Open
Questions, update that file by hand — the index file is yours to maintain.
