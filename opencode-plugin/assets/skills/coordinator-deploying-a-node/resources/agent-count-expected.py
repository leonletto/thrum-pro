#!/usr/bin/env python3
"""Expected GUI agent counts for a node, from the daemon's own agent.list.

Run ON the node (python3 standard library only, read-only). It asks the node's
daemon for agent.list over its unix socket, the same call the GUI makes, and
prints the numbers the GUI must show:

  rail_expected   the left rail heading "Agents (N)": local-origin rows, no
                  users, no retired rows, deduplicated by bare agent name.
  fleet_expected  the Fleet grid: sum of the five active category badges
                  (Working, Standby, EmptySession, RuntimeExited, Worktree).
                  Stale and Archived come from a separate query and are not
                  part of this sum.
  records_lacking_proof  records without origin_daemon or origin_repo_id. This
                  is INFORMATION ONLY. The GUI renders those rows too, so they
                  are counted in both expected numbers.

The rules mirror ui/packages/web-app/src/components/AgentList.tsx and
FleetGrid.tsx plus phaseCategory() in shared-logic utils/agentPhase.ts.

Usage:
  agent-count-expected.py [--socket PATH] [--from-file FILE]
  Default socket: $THRUM_SOCKET, else <repo>/.thrum/var/thrum.sock found from
  the current directory (follows .thrum/redirect). --from-file reads an
  agent.list result ({"agents": [...]}) instead, for tests.

Exit status: 0 numbers printed; 2 the socket or reply could not be used.
"""
import argparse
import json
import os
import socket
import sys

ACTIVE = {
    "active": "Working", "idle": "Working", "modal-blocked": "Working",
    "warm-hold": "Standby", "sleeping": "Standby",
    "empty-session": "EmptySession", "empty-session-sleeping": "EmptySession",
    "runtime-exited": "RuntimeExited", "empty-worktree": "Worktree",
}
INACTIVE = {"stale", "stale-contested", "not-known-alive", "retired", "purged"}
CATEGORIES = ["Working", "Standby", "EmptySession", "RuntimeExited", "Worktree"]


def find_socket():
    env = os.environ.get("THRUM_SOCKET")
    if env:
        return env
    d = os.getcwd()
    while True:
        t = os.path.join(d, ".thrum")
        if os.path.isdir(t) or os.path.isfile(t):
            redirect = os.path.join(t, "redirect")
            base = t
            if os.path.isfile(redirect):
                with open(redirect) as f:
                    base = f.read().strip()
            return os.path.join(base, "var", "thrum.sock")
        parent = os.path.dirname(d)
        if parent == d:
            raise SystemExit("agent-count-expected: no .thrum found; pass --socket")
        d = parent


def call_agent_list(path):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(30)
    s.connect(path)
    s.sendall((json.dumps({"jsonrpc": "2.0", "method": "agent.list", "params": {}, "id": 1}) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
    s.close()
    reply = json.loads(buf)
    if "error" in reply:
        raise SystemExit("agent-count-expected: agent.list failed: %s" % reply["error"])
    return reply.get("result", reply)


def bare(agent_id):
    return agent_id.split(":")[-1]


def compute(result):
    agents = result.get("agents") or []
    cats = {c: 0 for c in CATEGORIES}
    rail = set()
    lacking = []
    for a in agents:
        state = a.get("presentation_state") or "active"
        if state in ACTIVE:
            cats[ACTIVE[state]] += 1
        elif state not in INACTIVE:
            cats["Working"] += 1  # unknown states keep the Working default in the GUI
        if a.get("kind") == "agent" and not (a.get("origin_daemon") and a.get("origin_repo_id")):
            lacking.append(a.get("agent_id", ""))
        local = (a.get("origin") or "local") == "local"
        if local and a.get("kind") != "user" and a.get("phase") != "retired":
            rail.add(bare(a.get("agent_id", "")))
    return {
        "total_records": len(agents),
        "rail_expected": len(rail),
        "fleet_expected": sum(cats.values()),
        "fleet_categories_expected": cats,
        "records_lacking_proof": len(lacking),
        "lacking_proof_sample": lacking[:10],
    }


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("--socket")
    p.add_argument("--from-file")
    args = p.parse_args()
    try:
        if args.from_file:
            with open(args.from_file) as f:
                result = json.load(f)
        else:
            result = call_agent_list(args.socket or find_socket())
    except (OSError, ValueError) as e:
        print("agent-count-expected: %s" % e, file=sys.stderr)
        return 2
    print(json.dumps(compute(result), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
