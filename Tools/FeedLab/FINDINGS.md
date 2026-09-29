# Feed deep dive: Sep 22–29, 2026

What the merged feed (Today) actually does on real data, what's wrong with it,
and a source-agnostic way to build it that keeps working as sources change.
Nothing here changes the app; it's all measured with FeedLab.

## The data

| Set | What | How faithful |
| --- | --- | --- |
| 1 live snapshot | Sep 29, 12:40 ET. Every source fetched exactly as the app fetches it | Exact |
| 14 history snapshots | Sep 22–28, 1 pm and 9 pm ET each day | See below |

History snapshots:
- **Hacker News** is rebuilt from HN's own per-day archive, ranked at the snapshot time with HN's published formula. Checked against the live front page, the rebuild shares 11 of the top 20 stories, with order agreement (Kendall τ) of 0.51. Use it for broad patterns (source mix, ages, matching), not exact positions. It also leans a little toward fresh stories, since final points stand in for points at the time.
- **STAT and Marginal Revolution** are exact: their WordPress feeds page back, so each feed is rebuilt as it stood at the time.
- **bioRxiv and arXiv** are exact, via their APIs bounded to the time.
- **Nature** only exists for Sep 27 9 pm onward. Its feed doesn't reach further back.
- **Memeorandum** is switched off, a setting the app offers. Its archive pages are blocked by Cloudflare and its feed holds only the latest hour.

"Better" below means the goals the app states: every source gets seen, stories are fresh, and each ranked source's own judgement is respected. There's no reader-satisfaction data here. The app's `engagement.jsonl` would be the real test (see the end).

## Findings

### Ranking and merging

**1. Today is Hacker News plus Memeorandum. Biotech and RSS can't reach the top 20.**

| | Result |
| --- | --- |
| Live, all sources on | Top 10 is 8 HN, 2 Memo. Biotech first appears at #33, RSS at #28 |
| History, Memeorandum off | Top 20 is 20 of 20 HN in all 14 snapshots. Biotech first at #21–29, RSS at #21–30 |
| Best biotech or RSS score, every snapshot | 0.31–0.39 |
| Score needed to make #20 | 0.38–0.44 |

The cause is structural. A newest-first source gets a fixed placement of 0.5, so a brand-new story scores at most 0.5×0.5 + 0.15 = 0.40, below HN's 20th story. Top of the Stack is the only place biotech ever shows near the top, and RSS never gets a stone because `featuredSources` leaves it out.

**2. Placement depends on how many stories were fetched, not on page position.**

Placement is 1 − index / lane size. HN's lane holds 60 stories; Memeorandum's holds 24–40 (24 live). So Memeorandum's #12 scores 0.54 while HN's #12 scores 0.82. Scoring by position on a fixed 30-story page takes the live top 10 from 8 HN / 2 Memo to 5 / 5.

**3. Time is counted twice for ranked sources.**

HN and Memeorandum already decay stories with age on their own pages, and the app then adds recency on top. HN's own order survives the merge with Kendall τ 0.64 live and 0.68–0.89 across the history snapshots. Without the extra recency term it's 1.0, at the cost of a somewhat older top 10 (median age 7.6 h instead of 4.0 h live).

**4. Cross-posting almost never fires, and when it does it can take over Top of the Stack.**

- There were 2 matches in 15 snapshots, both the same link on both sides, and both correct.
- The headline matcher never fired. Every near-miss was a genuinely different story, so the matching is precise.
- These particular sources just rarely overlap, so the 35% weight on cross-posting is zero for nearly every story.
- Live, the only cross-posted story (HN's #38) became the first stone of Top of the Stack while sitting at #24 in the list.

### What goes into each lane

**5. bioRxiv shows the oldest preprints of the week.**

The API returns 30 per request, oldest first, and the app makes one request per category.
- Live, the app got Sep 22–23 bioengineering preprints for a window running to Sep 29.
- When the 24-story biotech lane is full, those old preprints are cut entirely: live, the lane had 0 bioRxiv items.

**6. Most Memeorandum stories have the wrong date and no Comments link.**

- The feed holds only the newest 15 posts, about an hour's worth. Live it covered 7 of the homepage's 26 stories.
- The other 18 of 24 get a stand-in date of midnight UTC on their permalink day, so they read as 17–41 h old. Memeorandum's own #1 story sat at #11.
- The permalink IDs (`260929p60`, `p74`) are numbered in posting order, which allows a reasonable estimate. Estimating dates this way moves the live top 10 only from 8/2 to 7/3, because recency is only 15% of the score, but it fixes the "41h ago" labels.

**7. The Memeorandum parser silently drops stories whose link carries a `searchurl` attribute.**

That's 2 of 26 live, all gift or unlocked links. The `searchurl` value is the clean article link, which would also match better against other sources.

**8. "Nature" is mostly other journals.**

The subject feed's 30 items are:

| Journal | Items |
| --- | --- |
| Scientific Reports | 10 |
| Nature Communications | 5 |
| Nature Biotechnology | 3 |
| Others | 12 |

Dates are day-level (midnight). On Sep 28 at 9 pm the biotech stone was "Bio-enhanced lightweight concrete: self-healing and mechanical performance".

**9. arXiv relevance matches keywords as substrings.**

"gene" matches "generative", "general" and "generator", and "cell" matches "excellent". Live, 1 of the 8 arXiv items was a general ML paper ("…Score-Based Generative Models Learn from Multimodal Data").

**10. STAT: all 8 items in the live lane were subscriber-only STAT+ stories.**

The app strips the "STAT+:" label, so readers can't tell they're paywalled.

**11. Weekends go stale.**

On Saturday and Sunday the newest biotech story was 23–47 h old. The same STAT story held the biotech stone for four snapshots running, from Friday 9 pm to Sunday 1 pm.

**12. All personal feeds share one lane, newest first, so a busy feed crowds out a quiet one.**

With STAT added as a feed beside Marginal Revolution, STAT took 13 of the 20 slots the app passes from RSS to the front page, and Marginal Revolution 7. On weekdays the split was about 14 to 6. A weekly blog would never make the cut.

## Hard-wired assumptions that break when sources change

These matter for onboarding (pick topics, get feeds), where sources become data rather than four fixed cases:

- **The cross-post bonus is divided by `Source.allCases.count − 1`.** Adding a fifth source shrinks every cross-post bonus by a quarter.
- **`hasEditorialOrder` is a switch over the four sources,** and anything not listed gets the fixed 0.5 placement from finding 1.
- **`featuredSources` is a fixed list,** so RSS, or any new source, never gets a stone.
- **Biotech is four feeds behind one source,** and all personal feeds are one source. Neither the ranking nor the reader can tell them apart, which causes finding 12.
- **Fetch and merge limits are set per source** (60/20, 40/20, 24/15, 32/20), and placement depends on them (finding 2).

## Variants tried on the same stories

Each variant re-orders exactly the stories the app put on the front page (`analyze.py`, full per-snapshot tables in `reports/variants.md`).

Averages over all 15 snapshots:

| Variant | Top 10 HN/Memo/Bio/RSS | First Bio / RSS | HN order kept (τ) | Median age top 10 |
| --- | --- | --- | --- | --- |
| current | 9.9 / 0.1 / 0 / 0 | #23.5 / #22.9 | 0.78 | 2.9 h |
| page placement | 9.7 / 0.3 / 0 / 0 | #18.9 / #17.4 | 0.89 | 3.1 h |
| Memo dates estimated | 9.8 / 0.2 / 0 / 0 | #23.4 / #22.9 | 0.78 | 2.9 h |
| no double recency | 9.8 / 0.2 / 0 / 0 | #23.5 / #23.1 | 0.99 | 3.6 h |
| reserved slots (#5, #10) | 8.0 / 0.1 / 0.9 / 1.0 | #10.7 / #6.7 | 0.78 | 2.8 h |
| diversity cap (≤60% per source) | 6.0 / 0.3 / 2.1 / 1.7 | #8.9 / #8.5 | 0.78 | 2.8 h |

Tuning weights inside the current formula doesn't get biotech or RSS seen. Only variants that make room explicitly do, and a plain cap does it without a freshness guard.

## A source-agnostic design: fair share

Implemented in `fairshare.py` and tested on the same data. The strategy knows nothing about any particular source. It only needs three things:

- **Channels.** A channel is one feed or one ranked page, and has a *kind*: ranked (it publishes an order) or chronological (newest first).
- **Groups.** What the reader sees as a source or topic. Channels belong to groups.
- **A weight per group:** its share of Today.

Standing, on a 0–1 scale for any kind of channel:

| Kind | Standing |
| --- | --- |
| Ranked | 1 − position / 30, by position on the page, whatever the fetch size |
| Chronological | Freshness on the channel's own clock. It halves every 2 × the channel's typical gap between posts, capped at 3–24 h |

Rules for building Today:

- **Cadence is inferred from timestamps, so no per-source settings are needed.** A weekly blog and a wire feed are each judged by their own rhythm.
- **Eligibility.** Ranked stories are always eligible. Chronological stories are eligible while standing is at least 0.35, and nothing older than 36 h is.
- **Cross-posts.** A story carried by n groups gains 0.25 × (n − 1) standing, however many sources exist.
- **Merge by weighted deficit round robin.** Each position goes to the group furthest below its share of the list so far, and that group takes its best story. Channels inside a group take turns the same way. A group with nothing eligible gives up its turn.

Results, averaged over 15 snapshots:

| | Top 10 HN/Memo/Bio/RSS | Top 10 age median / max | HN/Memo order kept |
| --- | --- | --- | --- |
| current | 9.9 / 0.1 / 0 / 0 | 2.9 h / 5.4 h | 0 of 15 |
| fair share, equal weights | 5.1 / 0.1 / 2.1 / 2.7 | 3.5 h / 12.9 h | 13 of 15 |

- **Live, all sources on:** the top 10 is 3 HN, 2 Memo, 3 biotech, 2 RSS. Each group's first story is at #1–4.
- **Adding a second, busy personal feed:** Marginal Revolution and STAT average 2.6 and 1.9 stories in the top 20. Under the current ranking it's 0.1 and 0.
- **Weights are the reader's knob:** HN 2, Memo 2, Bio 1, RSS 1 moves the averages to 5.7 / 0.2 / 1.7 / 2.4.
- **The HN/Memo order exceptions:** the 2 snapshots where order isn't kept are the 2 with a cross-posted story, which the bonus lifts.
- **Freshness settings matter.** The first cut (72 h, 48 h cap, 0.25) let the oldest story in the top 10 reach 38 h. The settings above bring it to 12.9 h:

| Max age | Half-life cap | Floor | Top 10 age median / max |
| --- | --- | --- | --- |
| 72 h | 48 h | 0.25 | 4.9 h / 37.7 h |
| 48 h | 24 h | 0.25 | 3.7 h / 17.6 h |
| 36 h | 24 h | 0.35 | 3.5 h / 12.9 h |
| 24 h | 12 h | 0.35 | 3.4 h / 11.8 h |

- **Fair share passes along whatever a channel supplies.** Live, Nature's concrete paper reached #6. Once every source is guaranteed a place, the lane fixes (findings 5–10) matter more, not less.

Why this holds up as sources change:
- Adding a source, ranked or not, adds a group or channel with a share.
- Removing one frees its share.
- A quiet feed isn't buried by a busy one.
- A group with nothing fresh steps aside instead of pushing stale stories up.
- Onboarding topics map directly to groups with weights, and discovered feeds become channels inside them.

## Recommendations, in order

1. **Fix what goes into the lanes.** These are cheap, and they matter under any ranking:
   - bioRxiv: request the newest page (from `total − 30`), not the oldest.
   - Memeorandum parser: accept extra link attributes, and prefer `searchurl`.
   - Memeorandum dates: estimate from the permalink sequence, or from the app's own first-seen record (`ReadingSessionStore`), instead of midnight UTC.
   - Nature: use `nature.com/nbt.rss`, or keep only `s41587` articles.
   - arXiv: match whole words.
   - STAT: keep the "STAT+" marker.
2. **Make sources data, not an enum:** channels with a kind and a group, and inferred cadence. Biotech's four feeds and each personal feed become their own channels. This is also the model onboarding needs.
3. **Build Today by fair share** (standing per channel plus weighted round robin) with the tuned freshness settings. It keeps each ranked source's own order.
4. **Make Top of the Stack generic.** Lead with a cross-posted story only when its standing is at least 0.5; otherwise take the first three stories from different groups in the fair-share order. Base the cross-post bonus on how many groups carry the story, not on how many sources exist.
5. **Later, learn the group weights from `engagement.jsonl`,** which the app already collects: share of opens and reading time per group. That's also the test "better" really needs: export it after a week or two and replay it against these strategies.

## What was implemented

Recommendations 1–4 are now in the app. Learning weights from reading history (#5) is not.

### Lane fixes

- **bioRxiv:** reads the newest page of each category.
- **Memeorandum:**
  - The parser accepts links with extra attributes, and a gift link's `searchurl` becomes the story's ID.
  - Every story gets its Comments link.
  - A story missing from the feed is dated by interpolating along the day's permalink numbers from the feed's dated stories, instead of midnight UTC.
  - A feed failure no longer takes the homepage down with it.
- **Nature:** reads the Nature Biotechnology feed, without correction notices.
- **arXiv and STAT:** match keywords as whole words.
- **STAT:** subscriber-only stories show "STAT+" as the outlet.
- **Personal feeds:** each feed contributes up to 12 of its own newest stories, instead of all of them sharing 32 slots.
- **Biotech:** the lane no longer has a shared cap of 24.

### Sources as data, and fair share

- Every story carries its channel and whether that channel publishes its own ranking (`FeedItem.channel`, `isRanked`), set by the service that fetched it.
- The engine and the cross-source matcher read only those. There is no list of sources, no hard-coded Top of the Stack sources, and no cross-post bonus scaled by how many sources exist.
- Top of the Stack takes the first three stories from different sources. A cross-posted story leads only when it stands in the top half of its own page.

### Two adjustments the replays called for

Replaying the first implementation showed two problems:

1. **bioRxiv filled most of the biotech share.** Its date-only timestamps all tie, and at 9 pm ET they even read as an hour old.
2. **arXiv and evening STAT never qualified.** arXiv surfaces a day after its papers' submission times, and STAT's hourly rhythm expired its stories within about 4½ hours.

The fixes:

- **A newest-first channel is now judged from its own newest story,** forgiving up to 24 h of lag. The 36-hour cap still applies.
- **By default, a source of ranked pages gets twice the share of a newest-first one,** since it has already chosen what matters. The weights stay the knob.

Over 16 snapshots, biotech's top-20 slots now spread across bioRxiv 36, STAT 22, arXiv 22 and Nature Biotechnology 11. The first implementation had bioRxiv at 84 of 128.

### Before and after, same data

`run.sh --rev f3889c2` compared with the new code, on the 14 history snapshots plus two live snapshots (12:40 and 15:13 ET, Sep 29):

| | History before | History after | Live before | Live after |
| --- | --- | --- | --- | --- |
| Top 10 (HN / Memo / Bio / RSS) | 10 / 0 / 0 / 0 | 5 / 0 / 3 / 2 | 8 / 2 / 0 / 0 | 3.5 / 2.5 / 2 / 2 |
| First biotech / RSS story | #19–22 / #21–24 | #2 / #3 | #28–33 / #28–29 | #3 / #4 |
| HN keeps its own order (τ) | 0.79 | 1.00 | 0.66 | 0.99 |
| Median age of the top 10 | 2.8 h | 3.1 h | 3.0 h | 4.4 h |
| Oldest story in the top 10 | 5.1 h | 13.3 h | 13.4 h | 17.9 h |
| Top of the Stack | HN + Bio | HN + Bio + RSS | HN + Memo, a weak cross-post first | HN + Memo + Bio |

The older top-10 stragglers are date-only preprints (bioRxiv, Nature Biotechnology), which count from midnight.

### Correction to the history data above

FeedLab's download cache cut file names at 200 characters, and arXiv's query URLs differ only after that point. So every history snapshot used Sep 22's arXiv response. That affected only arXiv's lane in history, and none of the findings rest on it. The cache key now includes a hash of the whole URL, and the history was recollected. Remaining caveat: in history, arXiv papers appear from their submission time, but live data shows the API lists them about a day later, so history slightly flatters arXiv.

## Reproduce

```sh
python3 Tools/FeedLab/collect.py live
python3 Tools/FeedLab/collect.py history --days 2026-09-22 … 2026-09-28 --times 13:00 21:00
Tools/FeedLab/run.sh --report Tools/FeedLab/reports/current.md
python3 Tools/FeedLab/analyze.py Tools/FeedLab/reports/current.md.lanes > Tools/FeedLab/reports/variants.md
python3 Tools/FeedLab/fairshare.py Tools/FeedLab/reports/current.md.lanes > Tools/FeedLab/reports/fairshare.md
```
