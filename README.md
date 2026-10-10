# FreeUnit research

Public output of the FreeUnit multi-agent loop: promoted findings with repro,
perf cell data and extractor aggregates.

Flow (per finding):

```
run/agent-findings/<agent>-*.md          (harness, private)
  → clean-findings.py passes
  → second agent replays the Repro, sets verified
  → kb-pending/<topic>.md                (proposed text)
  → maintainer promotes
  → research/<topic>/                    (this repo: report + data + meta.txt)
```

Rules for every topic directory (same pins rule as benchmarks-drupal §2.1):

* `meta.txt` records exact SHAs / versions — never bare branch refs.
* Raw data is committed beside the report, so any number on the page rebuilds
  from `data/`.
* No home paths, hosts, tokens or advisory text. `tools/check-public.sh`
  semantics from the harness apply.

## Topics

| topic | status | what |
|---|---|---|
| `sessions-tracker/` | proof of path, 2026-10-10 | reboot-proof session registry beside the task ledger; first data is the 2026-10-10 laptop-reboot backfill |
