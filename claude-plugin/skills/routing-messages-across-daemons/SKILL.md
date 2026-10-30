---
name: routing-messages-across-daemons
description: "Use when thrum send fails with unknown recipient, when sending a cross-box message to an agent on another daemon, when there is no second hop, when you need to route or relay through a paired peer, reach an agent on another box, or tmux send to a remote agent."
---

# Routing Messages and tmux Commands to Agents on Other Daemons

Routing and pairing are different things. Pairing connects two daemons directly. Routing sends a message through a directly paired peer to an agent that peer knows.

## Messages

- A daemon resolves a recipient from its local agents and from agents registered on its directly paired peers.
- To reach an agent on a daemon you are not paired with, run once on the SENDING daemon, per remote agent:

  ```bash
  thrum peer configure <relay-peer-name> add-agent <agent-name>
  ```

  `<relay-peer-name>` is the directly paired daemon that knows the agent.
- Then `thrum send --to @<agent-name>` routes through that peer.
- Run it on each side that needs to send.
- Pairing the two daemons with each other is not the fix.
- `thrum peer relayed add` and `thrum peer relayed grant` are not needed for delivery. They govern what a daemon accepts from a relayed origin.

## Verify

- `thrum peer list` shows directly paired daemons only.
- `thrum message get <id>` shows `(delivered)` per recipient. A send that returned without error is not proof of delivery.

## CLI notes

- `thrum peer relayed add --via` takes daemon IDs, not peer names.
- `thrum peer relayed grant` does not validate the capability key. The messaging key is `can_send_messages`.

## Unresolved agent records warning

After `add-agent`, the supervisor may report "Unresolved agent records" for the proxy rows, because reconcile asks the relay, which refuses with "owned by daemon X ... no second hop". A build with the reconcile owner pointer follows the named owner once and the warning clears. Older builds keep it. Do NOT delete those rows as the supervisor suggests: deleting them removes the routing.

## tmux

`thrum tmux send <agent> [<text>] [--keys K1,K2,...]` goes through the peer-routed `tmux.send` RPC. Both text and `--keys` modes work the same against a local session and a remote or peer session. Check the target's peer relationship with `thrum peer list` and confirm by effect on the target pane.
