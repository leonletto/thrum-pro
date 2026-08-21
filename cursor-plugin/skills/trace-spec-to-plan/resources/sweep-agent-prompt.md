# Sweep agent — shared instructions

> Dispatcher: write this file once, then give each agent ONLY its item list and its report path. Keeps dispatches short and identical.
> **Model:** sonnet · **Effort:** medium. The verdict call needs judgement; the searching does not.

---

For each assigned spec requirement: is it in the plan, and does the plan actually **plan to implement it** rather than merely name it?

## 🔴 WRITE YOUR REPORT TO YOUR ASSIGNED FILE FIRST, then append as you go

Create it with headings before any analysis. **Your final message is a SUMMARY; the FILE is the deliverable.**

Agents have completed full audits whose final text never reached the parent, and other dispatches left no artifact at all — that work is unrecoverable, and an idle notification is indistinguishable from "did nothing" and "did everything, and it vanished."

## CONSTRAINTS

- READ-ONLY git ONLY: `show`, `log`, `diff`, `grep`, `rev-parse`, `merge-base`, `status`. NEVER `checkout`, `reset`, `restore`, `stash`, `clean`, `rebase`, `commit`, `push` — in ANY directory.
- Operate ONLY in the worktree named in your dispatch. Write ONLY your report file.
- `rm -r`, never `rm -rf`. Work synchronously. No background children. Any sub-agent needs explicit `model:` and `effort:`.
- Read the plan in ~400-line windows. **Search the WHOLE plan for each of your items** — coverage may live in any phase.
- Verify code claims at the plan's **authored-against SHA** with `git show <sha>:<path>`. **The working tree may be on a different base**; reading it yields wrong line numbers.

## THE VERDICTS

| Verdict | Means |
|---|---|
| **PLANNED** | A task exists with concrete steps that would make the requirement true — files named, code or commands shown. |
| **NAME-ONLY** | The plan mentions, quotes, or asserts it — but no task carries out steps. |
| **ABSENT** | Not mentioned anywhere. |
| **PARTIAL** | Part planned, a named part not. Say which. |

🔑 **NAME-ONLY IS THE FINDING THAT MATTERS AND IT IS EASY TO MISS**, because good plans quote their spec often. **Quoting a rule is not implementing it.** A requirement restated in a warning box, a doc comment, an architecture paragraph, or a Definition-of-Done row is **NAME-ONLY unless a task carries out steps.**

**Worked example.** A function declared as a bare signature with a correct doc comment restating the spec, consumed by a task elsewhere — **NAME-ONLY**, because no step produces a body. The tell is not prose quality; it is that nothing produces the thing.

## THREE QUESTIONS PER ITEM

1. **Is there a task?**
2. 🔴 **Does the plan include every step to make it true — INCLUDING CREATING SUBSTRATE THAT DOES NOT EXIST YET?** Open the real struct/table/interface at the authored-against SHA. **A mechanism over a substrate that cannot hold the data is a SILENT NO-OP.** Weight this heaviest.
3. **Would anything FAIL if it regressed?** An implementation with no failing test has not achieved the property.

## FRAMING — do not get this backwards

🔴 **A gap is a MISSING STEP IN THE PLAN, never a defect in the spec.** If a requirement needs a field that does not exist, the correct finding is **"the plan is missing a task that adds the field"** — never "impossible", and never a suggestion to narrow the requirement. The spec is owner-ruled and correct; the plan is what is incomplete.

## REPORTING

- **Record PLANNED items too** — the complete map is the deliverable, not just the holes.
- **Report what you could not resolve**, naming the search you ran. Never guess. Pair any zero with a control showing the search can return something.
- 🔴 **If ALL your items come back PLANNED with zero NAME-ONLY, hand-verify two PLANNED rows at random and show your working.** An all-clear is the result most likely to be produced by not looking.

## OUTPUT (into your file)

A table: `Item · Spec line · Verdict · Plan task/line · One-line justification`
Then every NAME-ONLY / ABSENT / PARTIAL with the **concrete missing step**.
Then COVERAGE: items checked, and anything unresolved.
