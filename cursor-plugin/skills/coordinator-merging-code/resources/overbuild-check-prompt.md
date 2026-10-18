# Overbuild check — sub-agent prompt

Give this whole file to one judgment-tier sub-agent, with the inputs filled in.
It is read-only and takes about 10 minutes.

---

You are checking whether a branch built more than it was asked to build. Work
read-only in the repository named below: read files and run `git log`,
`git diff`, `git show` and `grep`. Do not build, run tests, edit, check out,
commit or push.

## Inputs

- Repository and trunk ref: `<REPO>`, `<TRUNK_REF>`
- Branch tip: `<TIP_SHA>`
- What was asked (the spec): `<ISSUE TEXT, PLAN PATH, DISPATCH MESSAGE>`
- Later rulings and gate findings that changed the ask, if any: `<LIST>`
- The owner's "tip ready" report: `<TEXT>`

## Steps

1. Read the ask. Write down, in your own notes, the list of behaviours it asks
   for. Nothing else counts as asked unless a later ruling or gate finding in
   the inputs adds it.
2. Read the change: `git diff --numstat <TRUNK_REF>...<TIP_SHA>`, the full
   diff, and every commit message (`git log <TRUNK_REF>..<TIP_SHA>`).
3. For each production file and each new function, type or field, trace it to
   one behaviour in the ask. Anything that does not trace is a finding unless a
   commit message, a ruling or a gate finding gives a concrete reason.
4. Look for these patterns:
   - **Invented scenario:** code that handles a case the ask never mentions,
     with no reproduction, log, failing test or gate finding showing the case
     happens.
   - **Duplicate machinery:** a new cache, lock, retry loop, deadline, queue,
     state or helper. Search the codebase for an existing one that does the
     same job; if one exists, the new one is a finding.
   - **Bundled feature:** a separate behaviour carried inside the fix.
   - **Unrequested guard:** a new refusal, deadline, bound, cap or
     authorization check that the ask did not request.
   - **Test volume:** more test lines than production lines is fine only when
     each test checks a distinct behaviour. Flag tests that check the same
     behaviour twice, tests that pin an old path or a past revision, and tests
     for an invented scenario.
5. Estimate what the simplest version that does exactly the ask would keep.

## Report (one page)

- **Verdict:** PROPORTIONATE (send to the gate), OVERBUILT (send back), or
  UNCLEAR (the coordinator decides).
- **Sizes:** production lines and test lines added, and your estimate for the
  simplest version.
- **Findings:** a numbered list. For each give the pattern, `file:line`, why it
  does not trace to the ask, whether a commit or ruling gives a reason, and
  what the simplest version would do instead.
- **Keep:** anything that looks large but is justified, with the reason, so it
  is not cut by mistake.

When the ask is thin (one line), say so and treat findings as pointers for the
coordinator to check, not as automatic rejections.
