# `watch_params.json` schema

Per-watcher config file at `.thrum/agents/<watcher>/watch_params.json` (resolved
through `.thrum/redirect` from a worktree, never a bare relative path). One file
per watcher or steward; a watcher is the only reader of its own file and a
coordinator (or the human) is its only writer. The watcher re-reads it at the
top of every cycle and after every self-restart: the file is truth, and a
message about a parameter change is only a nudge.

If the file itself is missing, or `roster` is missing or empty, the watcher is
not provisioned: it sends one `STARTUP FAULT:` message and shuts down rather
than idling.

| Field             | Type           | Required | Meaning                                                                                                                                                                                                                                    |
| ----------------- | -------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `watcher`         | string         | yes      | This node's own agent name.                                                                                                                                                                                                                |
| `parent`          | string         | yes      | Who to notify when something is wrong. `user:<name>` for the human at the root.                                                                                                                                                            |
| `model`           | string         | yes      | Chosen at launch (trust and cost tradeoff). A small model at low effort is enough for most rosters.                                                                                                                                        |
| `roster`          | array          | yes      | The agents this node watches. Each entry is an agent name, or an object `{"agent_id","hostname","tmux_session"}` (optional `runtime`) for an agent on another machine; the object form is what the SSH capture fallback uses. Never empty. |
| `cadence_active`  | duration       | yes      | Pane-capture interval while a roster member looks active.                                                                                                                                                                                  |
| `cadence_idle`    | duration       | yes      | Pane-capture interval while a roster member looks idle.                                                                                                                                                                                    |
| `restart_ctx_pct` | int            | yes      | Self-restart threshold on your own context percentage. Default `50`.                                                                                                                                                                       |
| `override`        | object or null | no       | `{cadence, reason, expires}`: a temporary widening. MUST carry `expires`; on expiry the watcher reverts to base cadence by itself.                                                                                                         |
| `pin_override`    | object or null | no       | `{target, model, effort, who, when, why, expires}`: a deliberate model or effort pin set by a coordinator. Distinct from `override`; do not merge them. `expires` is mandatory.                                                            |
| `rules`           | array          | no       | `[{when, cadence}]`: a deterministic table for cadence widening. The only sanctioned self-adjustment.                                                                                                                                      |
| `secondary_duty`  | string         | no       | A free-form extra duty written by a coordinator, done in addition to the primary duty.                                                                                                                                                     |

## `pin_override`

A deliberate coordinator override and an ordinary drifted pin look the same from
the pane alone. Without a recorded `pin_override`, the model-switcher's drift
correction would revert a deliberate change on its next cycle. The coordinator
sets `pin_override` for `target` and notifies the watcher; while it is live (not
expired) the watcher treats it as authoritative and does not touch `target`'s
model or effort. Write it by reading the whole file fresh, changing only
`pin_override`, and writing a temp file then an atomic rename; never edit in
place.

If `watch_params.json` does not exist for a watcher, do not create one to record
a `pin_override`. A watcher with no params file is unprovisioned: escalate.

## Example

```json
{
  "watcher": "steward1",
  "parent": "coordinator",
  "model": "<model>",
  "roster": [
    "coordinator_projecta",
    {
      "agent_id": "coordinator_projectb",
      "hostname": "build-box",
      "tmux_session": "coordinator_projectb"
    }
  ],
  "cadence_active": "5m",
  "cadence_idle": "10m",
  "restart_ctx_pct": 50,
  "override": null,
  "pin_override": null
}
```
