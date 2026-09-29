# FeedLab

Replays past moments of Grindstone's sources through the app's own feed code
(services, cross-posting, ranking, Top of the Stack) and reports how the
merged feed came out, so changes to the algorithm can be judged on real days
rather than one-off impressions. Not part of the app target.

## Run it

```sh
# 1. Collect snapshots. `live` is exactly what the app would fetch now;
#    `history` rebuilds past moments (US Eastern) from what the sources still serve.
python3 Tools/FeedLab/collect.py live
python3 Tools/FeedLab/collect.py history --days 2026-09-22 2026-09-23 --times 13:00 21:00

# 2. Replay them through the working tree's code (or --rev <commit>).
Tools/FeedLab/run.sh --report Tools/FeedLab/reports/current.md

# 3. Compare a change: replay the same data on the old and new code.
Tools/FeedLab/run.sh --rev HEAD~1 --report Tools/FeedLab/reports/before.md

# 4. Try ranking ideas on the app's own output, without changing the app.
python3 Tools/FeedLab/analyze.py Tools/FeedLab/reports/current.md.lanes > Tools/FeedLab/reports/variants.md
python3 Tools/FeedLab/fairshare.py Tools/FeedLab/reports/current.md.lanes > Tools/FeedLab/reports/fairshare.md
```

`FINDINGS.md` is the write-up of the first deep dive (Sep 22–29, 2026).

`run.sh` uses `swiftc` if installed, otherwise the official Swift image in
Docker (`mirror.gcr.io/library/swift:6.2-noble`; set `SWIFT_IMAGE` to change).


## What a snapshot is

A `live` snapshot is every request the app makes, answered now. A `history`
snapshot rebuilds a past moment:

| Source | What's replayed |
| --- | --- |
| Hacker News | its per-day archive (`front?day=`), ranked at the time with HN's gravity formula using final points; `live` records how closely this matches the real front page |
| Memeorandum | switched off: its archive pages are blocked (Cloudflare) and its feed holds only the latest hour |
| bioRxiv | the API over the week up to that day, cursor 0 exactly as the app asks (every page is also saved, to see what the app misses) |
| arXiv | the app's query, limited to submissions before the time |
| STAT, Marginal Revolution | rebuilt as they stood then from their paged WordPress archives (`?paged=N`) |
| Nature | the live feed with later entries removed; it only reaches back a day or two |

The Wayback Machine would allow exact past front pages, but it drops
connections from this environment's network.

Each snapshot's `snapshot.json` lists how close each capture came and anything
missing; the report repeats those notes, so gaps are visible rather than silent.

## How it works

`prep.sh` copies the app's non-UI sources, swaps `Utilities/FeedNetworking.swift`
for `replay/ReplayNetworking.swift` (answers each request from the snapshot),
points `FeedRankingEngine`'s clock at the replayed moment, and stands in small
shims for Combine and SwiftUI's `Color`. `eval/main.swift` runs a real
`FeedViewModel.refresh()` per snapshot and writes the report plus a `.json`
summary for comparing runs.

## The report

Per snapshot: the top 25 with source, age, placement and score; the source mix
of the top 10 and 20; how far down each source first appears; whether Hacker
News and Memeorandum keep their own order (Kendall τ); freshness; Top of the
Stack; lane health (including how much of bioRxiv's week the app actually
reads); every cross-posted story with its members, and similar headlines that
were not merged, for checking matches by hand. The overview adds how much of the
top 10 carries over between snapshots on the same day.
