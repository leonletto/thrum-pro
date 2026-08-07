---
name: plugin-update
description: "Use when changing, adding, reviewing or shipping ANY plugin skill, command, agent or hook - editing a SKILL.md, writing a new skill, fixing a skill description, running scripts/sync-skills.sh, updating the runtime plugin on a box, refreshing or reinstalling the plugin marketplace, or during any fleet deploy where agents must pick up new skills. Covers the mandatory plugin version increment (an edit is INVISIBLE to installed agents until the version moves), the YAML frontmatter rules that decide whether a skill is discoverable at all, how to verify a skill actually triggers, and how to check what is really installed versus what is merged."
---

# Thrum: Updating the Plugin (skills, commands, agents, hooks) — and why an edit alone changes nothing

> 🔴 **THE ONE-LINE VERSION: EDITING A SKILL FILE DOES NOT SHIP IT, AND A BROKEN
> `description:` DOES NOT FAIL LOUDLY — IT MAKES THE SKILL SILENTLY UNDISCOVERABLE.**
> Both failure modes were measured on primary on 2026-07-25 (S233). Neither produced an
> error, a warning, or a log line. In both cases the file on disk was correct.

## Why this skill exists — the incident, stated plainly

`coordinator_main` rolled a build to primary **without loading
`coordinator-deploying-a-box`**, skipped the mandated backup and the role re-render, and came
one rejected command short of `kill -9` on a daemon that was still writing its WAL.

It was not careless. **The skills listing it was served said the deploy skill was for
"Schema-Migrating" builds**, and it had just measured its own deploy as non-migrating
(71 → 71). It correctly concluded the skill did not apply.

That line was the H1 heading, not the `description:`. The description — which had been
widened months earlier to cover ANY deploy — **never reached any agent**, because the
frontmatter failed to parse and the loader fell back to the title. **The fix that widened
the scope edited the field nobody is served.**

Then, hunting siblings, the same defect was found to have made **five more skills vanish
from the listing entirely** — including `choosing-subagent-models`, which the coordinator
preamble names as a MUST-INVOKE before spawning any subagent, and
`closing-findings-while-warm`, the skill that fires on the act of deferring. Neither had
been invokable by anyone, on any box.

Then, verifying the fix, the installed plugin cache turned out to be **26 days stale** and
was still teaching **`Sonnet-ceiling / Haiku-floor tiering`** — a tier **banned since
2026-07-08**.

Three layers, one shape: **the artifact was right and the thing actually loaded was not.**

---

## 0. Write the rule, not the discussion

Skill content loads into context every time the skill triggers. Prose here is a
tax paid at every use, by every agent.

- State the correct behaviour, then stop.
- Leave out what went wrong, why it was wrong, and what not to do.
- No counter-examples, no history, no measurements. Evidence belongs in the bead
  that sourced the fix. **The bead references the change; the change NEVER
  references the bead.** This is a product — customers do not care about our
  internal development particulars, and shipped content must not carry issue IDs.
- Cap sections in **words, not lines** — one line holds a thousand words and
  satisfies a line cap exactly.

If a reader would act correctly without a sentence, delete that sentence.

## 1. Frontmatter rules — these decide whether a skill can be found at all

### 1.1 🔴 `description:` MUST be a single-line QUOTED scalar

```yaml
---
name: my-skill
description: "Use when ... - trigger phrase, trigger phrase, trigger phrase. Loads ..."
---
```

**NEVER this** — a plain (unquoted) multi-line scalar:

```yaml
description:
  Use when ... . Loads the deploy runbook: verifying the SHA,   # <-- ": " HERE
  install-before-restart ordering ...
```

**A plain YAML scalar cannot contain `": "` (colon followed by space).** It is a syntax
error, and the parser discards the WHOLE frontmatter block. Measured consequences, both
real, both silent:

| Symptom | What you see | What it means |
|---|---|---|
| Skill listed with its **H1 heading** as the description | A plausible one-liner that may be scoped WRONG | frontmatter dropped, title used as fallback |
| Skill **absent from the listing entirely** | Nothing. The skill simply is not offered. | frontmatter dropped, no fallback available |

**The second is worse and quieter.** A skill that does not appear cannot be missed. Nobody
gets an error; agents just never invoke a discipline that exists.

### 1.2 Avoid `": "` inside the description even when quoted

Quoting makes it legal YAML. Keep it out anyway — use ` - ` or a comma. Some consumers
parse frontmatter with naive line-splitting rather than a YAML library, and a quoted colon
is one implementation detail away from breaking again. Costs nothing; removes a class.

### 1.3 Keep the H1 carrying the real scope

The H1 is the **fallback surface**. If the frontmatter ever breaks again, the H1 is what
agents are served. So it must not contradict the description.

**The deploy skill's H1 said "Schema-Migrating" while its description said "ANY build,
migrating or not". That mismatch is what caused the incident.** Whenever you widen or
narrow a skill's scope, change BOTH.

### 1.4 Apostrophes and inner quotes

Inside a double-quoted scalar, apostrophes (`don't`, `wake's`) are fine. Convert inner
double quotes to single quotes.

---

## 2. Checking — run the sweep, then confirm its hits

### 2.1 The sweep

```bash
python3 - <<'PY'
import glob, re
files = sorted(glob.glob('.claude/skills/*/SKILL.md') + glob.glob('claude-plugin/skills/*/SKILL.md'))
bad = []
for f in files:
    t = open(f, encoding='utf-8').read()
    m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
    if not m: bad.append((f, 'no frontmatter')); continue
    fm = m.group(1)
    dm = re.search(r'^description:(.*)$', fm, re.M)
    if not dm: bad.append((f, 'NO description key')); continue
    inline = dm.group(1).strip()
    if inline and inline[0] in '"\'>|': continue     # quoted / block scalar: colons legal
    body = [inline]
    for line in fm[dm.end():].split('\n'):
        if re.match(r'^\s+\S', line): body.append(line)
        elif line.strip() == '': continue
        else: break
    if ': ' in ' '.join(body): bad.append((f, 'plain scalar contains ": "'))
print(f"scanned={len(files)}  defective={len(bad)}")
for f, w in bad: print("  ", f, "->", w)
PY
```

### 2.2 Confirm every sweep hit against the served listing

The sweep produces a candidate list. The served listing decides. Check each flagged
skill against it before changing anything.

### 2.3 Use short grep keys, and give every zero a control

Block-style descriptions wrap at ~80 columns, so a key long enough to straddle a line
break returns zero on text that is present. Keep keys short enough to sit on one line,
and confirm any zero with a second key.

### 2.4 Name the directory you mean

Version directories do not sort the way you expect: `0.11.0-dev.1.1/` sorts before
`0.11.0-dev.1/`. Write the path out; never select one with `ls | tail -1`.

---

## 3. The update procedure — all five steps, in order

```bash
# 1. EDIT in claude-plugin/ — the source of truth. Never edit a synced copy.

# 2. SWEEP (§2.1) and fix anything it flags.

# 3. PROPAGATE to the other runtimes.
scripts/sync-skills.sh

# 4. 🔴 INCREMENT THE PLUGIN VERSION — ALL FOUR MANIFESTS, IN SYNC.
#    claude-plugin/.claude-plugin/plugin.json
#    .claude-plugin/marketplace.json                      <-- the installer keys on THIS
#    codex-plugin/plugins/thrum/.codex-plugin/plugin.json
#    cursor-plugin/.cursor-plugin/plugin.json
#    (opencode-plugin/package.json is an INDEPENDENT version line — leave it.)
grep -rn '"version"' --include="*.json" .claude-plugin claude-plugin/.claude-plugin \
    codex-plugin/plugins/thrum/.codex-plugin cursor-plugin/.cursor-plugin
python3 -c "import json;[json.load(open(f)) for f in ['claude-plugin/.claude-plugin/plugin.json','.claude-plugin/marketplace.json']]" # still valid JSON?

# 5. COMMIT + PUSH. Then each box PULLS, and the operator refreshes the plugin there.
```

### 3.0 Codex parity is automatic — the display-name map is cosmetic only

`scripts/sync-skills.sh` derives the codex skill set from the source tree. **A new skill
reaches codex with no script edit.**

The `case` block near line 273 only prettifies names whose derived form reads badly. **A
name missing from it costs cosmetics, never presence** — the script says so itself.

```bash
grep -c 'PARITY_SKILLS' scripts/sync-skills.sh    # 0 - the old allowlist is gone
```

Add a `case` line only when the derived display name reads badly. Skip it otherwise.

### 3.1 🔴 WHY STEP 4 IS MANDATORY AND NOT HOUSEKEEPING

The thrum marketplace `source.path` is a **LOCAL PATH** (the repo itself), and the install
cache is keyed by **VERSION**:

```
~/.claude/plugins/cache/thrum/thrum/<version>/skills/...
```

**If the version string has not changed, the installer sees a match and skips re-copying.**
Your edit, your merge and your push are all irrelevant to what agents load.

**MEASURED 2026-07-25:** the manifest had sat at `0.11.0-dev.1` since **2026-07-11**; the
cached content was dated **2026-06-29**. Every skill edit for **26 days** was invisible to
every installed consumer, and the cache was still serving a **banned model tier**. A
marketplace *refresh* did not fix it — only bumping the version and reinstalling did.

⚠️ **A partial bump is worse than none** — the runtimes then disagree about which build they
are. Move all four together.

---

## 4. Verifying — BY EFFECT, with controls

**Exit code 0 from the sync script proves nothing.** Neither does a merged commit.

```bash
NEW=~/.claude/plugins/cache/thrum/thrum/<new-version>/skills   # BY NAME (see §2.4)

# a) the cache is actually new
stat -f "%Sm" -t "%b %d %H:%M" "$NEW/<skill>/SKILL.md"          # expect: today

# b) installed == source, byte for byte
diff -q "$NEW/<skill>/SKILL.md" claude-plugin/skills/<skill>/SKILL.md

# c) the stale text is GONE, with a control proving the key can match
grep -c "<retired-string>" "$NEW/<skill>/SKILL.md"              # expect 0
grep -c "<string-that-IS-there>" "$NEW/<skill>/SKILL.md"        # expect >0  <-- the control
```

**d) The listing itself is the only real test.** Reload plugins, then read the served
description and check it carries a **distinctive token you just changed** (a reworded phrase,
a hyphen where an em-dash used to be). Matching text you did not touch proves nothing.

**e) PRE-REGISTER THE PREDICTION, INCLUDING A CONTROL THAT MUST *NOT* CHANGE.** Before the
reload, write down which skills must gain descriptions and **which must stay exactly as they
are**. Without the negative half you cannot tell your fix from an unrelated reload artifact.
Nominate a skill you did not touch as the control.

---

## 5. 🔴 KNOWN LIMIT — DO NOT CHASE THIS ONE INTO THE FILES

Some skills list **bare** (name, no description) even with correct, quoted, verified-installed
frontmatter. **The bare set VARIES BETWEEN RELOADS and includes skills nobody has edited** —
`thrum:thrum` and `coordinator-maintaining-memory` were described in one listing and bare in
the next, same files, same session.

⇒ That is **harness-side**, most likely a size budget on the listing, and it is **not fixable
by editing skill files**. Adding a long description to one skill may cost another its
description.

**If a skill lists bare and its file is correct and its installed copy matches: STOP.** Do
not rewrite it, do not "normalise" it again, do not file it as a content defect. Note it and
move on. The only lever that plausibly helps is **fewer or shorter descriptions overall**.

---

## 6. Fleet — the plugin pass is NOT the roles pass

Three different things, routinely conflated, each with its own verification:

| Pass | What it updates | Who runs it |
|---|---|---|
| `make install` + daemon restart | the **binary** | the box's own coordinator, locally |
| `thrum roles refresh` then `thrum roles deploy` | **role preambles** | the box's own coordinator |
| plugin refresh / reinstall | **skills, commands, hooks** | **the operator (Leon)** |

**A box can have a current binary, current preambles, and month-old skills.** When reporting
a deploy, **say which pass you verified** — "deployed" that silently covers all three is how
this stayed hidden.

**Order for a fleet skill change:** land + push → each box `git pull` → operator refreshes the
plugin per box. Coordinators cannot self-serve the plugin pass; they can only make the box
ready for it.

---

## 6a. 🔴 ANTI-PATTERNS THAT PREVENT ACTIVATION — every one of these fired on 2026-07-25

**A skill that exists, is correct, and is installed can still fail to fire.** These are the
measured ways, in the order they bit. The first four are properties of the FILE; the last
three are properties of the READER, and those are the ones no sweep will ever catch.

### A1. The H1 is scoped NARROWER than the description — **this is the one that caused the incident**
`# Coordinator: Deploying a SCHEMA-MIGRATING Build to a Box` against a description covering
ANY build. When the frontmatter dropped, the H1 was all that was served. The coordinator had
just measured its deploy as **non-migrating** and correctly concluded the skill did not apply.
**A correct decision from a wrong label.** ⇒ Never let the H1 be narrower than the trigger
scope, because it is the fallback and it is the only surface that survives a parse failure.

### A2. The scope fix edits `description:` and leaves the H1 alone
Somebody had already widened this skill to "ANY deploy" — in the field nobody was served.
**A trigger fix applied to the invisible surface is indistinguishable from no fix at all**,
and it is worse than none, because it discharges the obligation to make a real one.

### A3. The description lacks the words the agent will actually be thinking
Triggers must be phrased in **task vocabulary at the moment of use**, not in the skill's
formal title: "fleet roll", "rolling the fleet", "deploying primary", "make install plus
daemon restart", "ship to a box". An agent about to roll the fleet does not think
"schema-migrating build". ⇒ **Write the trigger list from what the operator will type or the
agent will say, then verify one of those phrases appears verbatim.**

### A4. The skill lives outside `claude-plugin/` and is therefore not distributed at all
`coordinator-deploying-a-box` lives in `.claude/skills/` and `thrum-agent-dev-skills/`, **not
in `claude-plugin/skills/`**. So it is not synced to the other runtimes, is not carried by the
plugin version, and reaches another box only if that box has the repo checked out.
⇒ **If a skill must exist on every box, it belongs in `claude-plugin/skills/`.** A
project-local skill is a single-box artifact wearing a fleet-wide name.

### A5. 🔴 THE READER SUBSTITUTES ITS OWN SUMMARY FOR THE SKILL
The coordinator had a restart snapshot whose §5 listed the deploy mechanics as bullets. It
worked from those and never invoked the skill — and the bullets were a faithful subset that
happened to omit the backup, the role re-render, and the wedge discriminators.
🔑 **A summary you wrote for yourself reads as complete precisely because you wrote it.** The
snapshot cannot list what you did not know to include, and its omissions are silent.
⇒ **A snapshot is a pointer to the procedure, never a replacement for it.** If a skill covers
the task, invoke the skill even when you believe you remember it.

### A6. Another agent names the skill and you do not take the cue
`coord_thrum_zarambp14`'s FIRST message said it was driving its deploy *via
coordinator-deploying-a-box*. That was read, acknowledged, and not acted on.
⇒ **A peer naming a skill for the task you are doing is a trigger.** Treat it as one.

### A7. Momentum — a terse authorization reads as "skip the preliminaries"
"We are ready, roll the fleet" is authorization for the OUTCOME, never a waiver of the
PROCEDURE. The urgency of a green light is exactly when the runbook is most worth loading and
feels least necessary.

---

## 7. Red flags — STOP

- Editing a skill and calling it shipped **without bumping the plugin version**.
- A `description:` on its own line with the value indented beneath it.
- Any `": "` inside a description.
- An H1 whose scope contradicts the description (**this caused the incident**).
- Editing a **synced copy** (`codex-plugin/`, `cursor-plugin/`, `opencode-plugin/`) instead of
  `claude-plugin/` — the next sync overwrites it.
- Reporting a skill fix as verified **without reloading and reading the served listing**.
- Reading a zero from a grep whose key might wrap across lines, with no control.
- `ls | tail -1` to pick a version directory.
- Concluding "deployed" when only the binary moved.
