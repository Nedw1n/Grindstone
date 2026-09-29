# FeedLab

Replays past moments of Grindstone's sources through the app's own feed code
(services, cross-posting, ranking, Top of the Stack) and reports how the
merged feed came out, so changes to the algorithm can be judged on real days
rather than one-off impressions. Not part of the app target.

## Run it

```sh
# 1. Collect snapshots (US Eastern times). Needs network access to the sources
#    and to web.archive.org; responses are cached under data/.cache.
python3 Tools/FeedLab/collect.py --days 2026-09-25 2026-09-26 2026-09-27 2026-09-28 \
    --times 08:00 13:00 18:00 22:00

# 2. Replay them through the working tree's code (or --rev <commit>).
Tools/FeedLab/run.sh --report Tools/FeedLab/reports/current.md

# 3. Compare a change: replay the same data on the old and new code.
Tools/FeedLab/run.sh --rev HEAD~1 --report Tools/FeedLab/reports/before.md
```

`run.sh` uses `swiftc` if installed, otherwise the official Swift image in
Docker (`mirror.gcr.io/library/swift:6.2-noble`; set `SWIFT_IMAGE` to change).

`selftest.py` checks the collector and replay against canned responses with no
network: `python3 Tools/FeedLab/selftest.py --out Tools/FeedLab/build/selftest-data`
then `run.sh --data Tools/FeedLab/build/selftest-data`.

## What a snapshot is

| Source | What's replayed |
| --- | --- |
| Hacker News | Wayback Machine capture of the front page nearest the time (page 2 when archived), as the `topstories` and item JSON the app requests |
| Memeorandum | memeorandum's own archive page for that time; its feed isn't archived, so each story is dated by its first appearance in the hourly archives |
| bioRxiv | the API over the week up to that day, cursor 0 exactly as the app asks (every page is also saved, to see what the app misses) |
| arXiv | the app's query, limited to submissions before the time |
| STAT, Nature, Marginal Revolution | the feed capture nearest the time, else the live feed, with later entries removed |

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
