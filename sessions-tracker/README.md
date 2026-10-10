# sessions-tracker — reboot-proof session registry beside the task ledger

Status: prototype, 2026-10-10 (pi/strace). Lives under `run/` (gitignored, any agent may
write), so it needs no maintainer approval to try. Promotion to `tools/session` + docs is
a separate patch decision.

## Why this exists

The laptop rebooted 2026-10-10 and every live session died silently: pi, dsh `web`,
opencode runs. The task ledger (`docs/task-ledger.md`) tracks **tasks** (`pr/588`,
`job/perf-remeasure-1.37.0`) — it knows a claim went stale only when `task reap` runs and
the owner never reports. It does not track **sessions**: who is alive, on which host, how
much context they hold, what they burned. After a reboot the first 8–15 tool calls of every
fresh session re-derive exactly that (ledger §1).

This tracker is the session side of the same design: one file per session, frontmatter for
mutable state, `## Next` for resume, `## Log` in the bus grammar. Reboot-proof because the
state is on disk, heartbeat-driven because liveness is a timestamp, not a process.

## Why files, not sqlite

Same verdict as the ledger (§2) and the bus (agent-coordination §1): a model with no tool
can `cat` a session file; `rg`, `tail` and `awk` read the registry; it survives every tool
crash and works over ssh; no lock server, no schema breaks (beads/Dolt lesson, ledger §2).
`session ls` is the `index.tsv`; `rg` is the query engine; the nightly extractor is the
aggregator. If we ever need SQL, generate sqlite from the files — never the reverse.

## Layout

```
run/sessions-tracker/
  README.md            this file
  hermes-bridge.md     how the hermes bot consumes this + GitHub App events
  tools/session        CLI (python3 stdlib, flock, best-effort bus mirror)
  sessions/<agent>-<shortid>.md   one per session, 0600 when embargoed (same rule as ledger §3)
```

Session file: `id agent session role task host cwd status started heartbeat ttl_min
tokens_in tokens_out tokens_cache cost_usd ctx_pct turns model reason updated` + `## Next`
(max 3 lines, resume contract) + `## Log` (bus lines, `{"session": id, "task": ...}` tail —
the same line is also in `run/inbox/bus.log`, so `rg '"session":"pi-..."' bus.log` matches).

`status`: `live` → `dead` (reboot/crash/reap, keeps `## Next` → resumable) → `done`
(closed with reason). `dead` + non-empty `## Next` = "resume me"; `dead` + empty = garbage.

## Usage (context + cost tracing)

Every agent heartbeats when it starts, every ~15 min on long jobs, and on stop:

```bash
export SESS_ROOT=$HARNESS/run/sessions-tracker/sessions INBOX_SENDER="reviewer@dsh"
session register --agent dsh --session c08ec7ff --role reviewer --task pr/600 --model deepseek-flash \
  --next "PR 600 report-only review, anchored prompt"
session heartbeat dsh-c08ec7ff --ctx 23 --turns 14 --tokens-in 260000 --cache 2540000 --cost 0.003
session next dsh-c08ec7ff "findings filed, waiting on maintainer lease-push"
session done dsh-c08ec7ff --reason "review posted, no GH post per authority table"
session reap --ttl 60        # cron: marks live-but-silent sessions dead (reboot detector)
session ls --stale --stale-min 60
session brief pi-01a123d5-358 --short   # resume card: status, Next, last 5 lines
```

Where the numbers come from (no new metering, reuse the extractors):

| agent | tokens/cost source | context % source |
|---|---|---|
| pi | `tools/session-extract/pi.py` (`usage.input/output/cacheRead`, `cost.total`) | prompt tokens ÷ model window (spark 200K) at heartbeat |
| dsh | `tools/session-extract/dsh.py` (steps, cache read) | steps ÷ 300 stop-loss, or prompt chars ÷ window |
| claude | `tools/session-extract/claude.py` | `quota-state` + transcript tokens |
| codex | `tools/session-extract/codex.py` (`token_count`, rate limits) | 5h/weekly % |
| opencode | `opencode.db` `session` table | same table |
| hermes | agent.log `in=` p50/p90 | compaction threshold math (config.yaml comment) |

Backfill rule (mirrors ledger §6): an agent that never called the CLI still lands in the
registry a day late — `session register --agent X --session Y` + heartbeat from the
extractor line, reason `backfilled <date>`. The 2026-10-10 reboot backfill is the example:
two dead pi sessions with real token counts (big one: 203 turns, 3.8M in, 35M cache, $10.57).

## Lease interaction (no second source of truth)

The ledger owns tasks, leases and permission. The tracker owns liveness, context and cost.
They join on `task` + `session` keys: `task show pr/588` lists claims; `session ls` shows
whether the claimant is alive. `task reap` expires claims by TTL; `session reap` expires
liveness by heartbeat; a session marked `dead` with an open claim is the nudge to run
`task handoff` or `task reap`. A task line is never permission (ledger §2) and a session
line is never a claim — same rule, both sides.

## Cron (3 lines, on the maintainer box)

```cron
*/15 * * * * SESS_ROOT=$H/run/sessions-tracker/sessions $H/run/sessions-tracker/tools/session reap --ttl 60
0 2 * * *  $H/tools/session-extract/nightly.sh --backfill-sessions  # extractor lines → register+heartbeat
* * * * *  SESS_ROOT=$H/run/sessions-tracker/sessions $H/run/sessions-tracker/tools/session ls --stale --stale-min 60 | mail -s "stale sessions" $ME
```

## Metrics (prove it in a week, same style as ledger §10)

1. Resume cost after reboot: `brief --short` → first edit, target ≤3 tool calls (ledger metric 1).
2. Ghost claims: live tasks owned by `dead` sessions, target 0 at each daily check.
3. Cost per task: `session ls` + extractor join = tokens/$ per task id (fills the spending-table gap, ledger §6).
