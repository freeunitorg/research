# hermes bridge — the freeunit bot as watcher + coordinator + research contributor

Status: sketch, 2026-10-10. The bot is `bots/freeunit` in hermes-playground (deepseek-flash,
kanban + cronjob + memory + session_search toolsets). It already runs 24/7 where the laptop
does not. This note gives it three jobs that close the multi-agent loop without giving it
any authority it must not have.

## Authority (non-negotiable, from agent-coordination §2)

The bot is `watcher` + `reviewer` lanes only. It never pushes, never force-pushes, never
posts on GitHub as itself, never reads `run/ghsa/` or embargoed (`0600`) session files, never
treats a ledger/task line as permission. It writes: its own kanban, `run/agent-findings/`,
`run/inbox/` lines, and research files in the **fork** (below) — never `docs/`, `skills/`,
`tools/` except as a patch for the maintainer. Same table as every other non-Claude agent.

## Job 1 — watch: GitHub App events → tasks + sessions

Today the bot polls. Tomorrow it receives. Both end in the same two writes.

Poll mode (works now, over ssh from the bot host with its own key + `LAB_ENV`):

```bash
# every 10 min: what died, what is ready, what needs a reviewer
session ls --stale --stale-min 60          # ghosts after a reboot like 2026-10-10
task ready --role reviewer                 # open tasks with deps done, no live owner
task reap                                  # read-only preview; the maintainer cron applies
```

Each new GitHub event (PR opened/sync, CI failure, review requested) becomes **one bus line
+ one task note**, never a direct action:

```
<poll-ts> watcher@hermes fact <id> PR 642 synced <sha>, CI 3/39 red {"pr":642,"task":"pr/642","sha":"..."}
```

App mode (when the GitHub App lands): the webhook receiver does the same two writes and
nothing else — event → `inbox send` + `task note`. The receiver holds no checkout, no token
beyond `gh read`, no merge logic. Review/merge stays with the maintainer + Claude/Codex lanes.

## Job 2 — coordinate: the board other agents read

The bot owns no task, so it can hold the board honestly:

* `session ls` → kanban "agents" column: live/dead per host, ctx% hot list (>70% = offer handoff).
* `task ready` → kanban "ready" column, one card per task with `brief --short` + lease state.
* Stale-heartbeat ping: a `request` line to the dead session's role (`ttl_min 30`), then a
  `fact` when `reap` fires — so the bus shows the reboot (2026-10-10) as data, not silence.
* Spending rollup: nightly join of extractor lines + `session ls` → tokens/$ per task, posted
  as a `finding` file. This is the number the spending table (§3) lacks.

Handoff contract: the bot never reassigns. It writes `task next`-quality suggestions as bus
`request`s; the owner or maintainer runs the `handoff`. A bot line that looks like permission
is a bug.

## Job 3 — research fork: contribute without touching the server

New repo (fork-side, not freeunitorg/freeunit): `freeunitorg/research` or a bot-owned fork.
What lands there: promoted findings with repro, perf cell data (`results/<run-id>/` shape from
the drupal-bench plan), extractor aggregates, hermes session digests. Flow:

```
run/agent-findings/<agent>-*.md → clean-findings.py → verified → kb-pending/<topic>.md
  → maintainer promotes → research/<topic>/ (report + data + meta.txt, same pins rule as
     benchmarks-drupal §2.1: composer.lock / SHAs recorded, no bare branch refs)
```

The bot drafts the research PR body from the task gates + session costs; the maintainer
merges. The bot's own Hermes memory (SOUL.md, session_search) stays its own; only the weekly
`done`-task export crosses over, after the findings scrub (ledger §9).

## Minimal wiring (this week)

1. Bot host gets `run/sessions-tracker/tools/session` + `tools/task` on PATH over ssh, read
   access to checkouts, group write to `run/inbox run/agent-findings run/sessions-tracker`
   (same setgid pattern as the second-Unix-user rule, §2).
2. One cronjob in the bot config: poll loop above, 10 min, `dispatch_in_gateway: true` so a
   second bot never double-posts.
3. One kanban board: columns `agents / ready / blocked / done`, cards link `task brief` + `session brief`.
4. Research fork created empty; first test PR is this tracker (README + tool + backfilled
   2026-10-10 reboot data) — proves the path before any real finding flows through it.
