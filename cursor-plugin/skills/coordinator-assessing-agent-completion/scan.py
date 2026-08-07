#!/usr/bin/env python3
"""Rank alive agents by whether their last message reads as terminal.

This is an INFORMATION source. It ranks and quotes; it does not conclude, and it
deliberately has no flag that reaps, kills, or changes a phase. The reading agent
makes the judgment call using the gate and containment checks in SKILL.md.

Usage:
    thrum tmux connect < /dev/null | python3 scan.py [worktree-root]

Reads `session|@agent` lines on stdin (see SKILL.md for the awk that produces
them). Default worktree root is ~/.thrum/worktrees/thrum.
"""

import datetime
import glob
import json
import os
import re
import sys

# Phrases an agent uses to declare it holds nothing. Matching one makes an agent
# a CANDIDATE, never a decision -- the blocker check in SKILL.md is what decides.
TERMINAL = (
    "standing by", "standing down", "stand down", "task done", "no further action",
    "nothing to add", "nothing further", "completion report sent", "inbox is clear",
    "inbox clear", "no action needed", "no reply needed", "idle", "held pending",
    "awaiting", "nothing owed", "work is complete", "done and reported",
)


def slug(path):
    """Claude Code's project-dir naming (thrum-ymqha): every character that is
    not [A-Za-z0-9] becomes '-' -- not just '/' and '.'. Mirrors
    internal/transcript/parsers/claude.go's EncodeClaudePath exactly for ASCII
    input. The prior narrower rule silently produced the wrong directory name
    (and a false "no transcript" result) for any worktree/agent path
    containing an underscore, e.g. orch_b, impl_*, researcher_*.
    """
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def last_assistant_text(path):
    """Last non-empty assistant text block, or '' if none."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") != "assistant":
            continue
        for block in rec.get("message", {}).get("content", []):
            if isinstance(block, dict) and block.get("type") == "text":
                text = " ".join(block.get("text", "").split())
                if text:
                    return text
    return ""


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.thrum/worktrees/thrum")
    projects = os.path.expanduser("~/.claude/projects")
    now = datetime.datetime.now(datetime.timezone.utc)

    rows, no_transcript = [], []
    for line in sys.stdin:
        line = line.strip()
        if "|" not in line:
            continue
        session, agent = line.split("|", 1)
        files = glob.glob(os.path.join(projects, slug(os.path.join(root, session)), "*.jsonl"))
        if not files:
            # NOT evidence the agent is gone -- see SKILL.md.
            no_transcript.append(agent)
            continue
        newest = max(files, key=os.path.getmtime)
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(newest),
                                                datetime.timezone.utc)
        text = last_assistant_text(newest)
        low = text.lower()
        hits = [p for p in TERMINAL if p in low]
        rows.append(((now - mtime).total_seconds() / 3600.0, agent, hits, text))

    rows.sort(key=lambda r: (not r[2], -r[0]))

    print(f"alive with transcripts: {len(rows)}   no transcript: {len(no_transcript)}")
    print("\nLAST MESSAGE READS AS TERMINAL -- an observation, not a recommendation.")
    print("Name each one's blocker and prove it dead before concluding. See SKILL.md.\n")
    any_candidate = False
    for idle, agent, hits, text in rows:
        if not hits:
            continue
        any_candidate = True
        print(f"  {agent:<28} idle {idle:5.1f}h  [{', '.join(hits)}]")
        print(f"    {text[:150]}")
    if not any_candidate:
        print("  (none)")

    print("\nNOT terminal -- still working or mid-exchange:")
    for idle, agent, hits, _ in rows:
        if not hits:
            print(f"  {agent:<28} idle {idle:5.1f}h")

    if no_transcript:
        print("\nNo transcript found (NOT evidence of absence):")
        for agent in no_transcript:
            print(f"  {agent}")

    print("\nIdle hours are unreliable after any fleet broadcast -- your own "
          "traffic resets every recipient's clock. Rank by content, not time.")


if __name__ == "__main__":
    main()
