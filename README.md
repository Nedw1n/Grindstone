# Grindstone

A personal news aggregator for iPhone, iPad, and Mac. It pulls Hacker News,
Memeorandum, a set of biotech journals, and your own RSS feeds into one ranked
list, and flags stories that show up in more than one place.

## Using it

- **Today** – the merged front page. Tabs along the top filter by source.
  **Top of the Stack** sets the three stories that matter most as a cairn:
  the first stories from three different sources, led by a cross-posted story
  when it also ranks high on its own page. Below it,
  swipe right to save and left to mark read. Read stories drop to a lighter
  type weight. The Options menu hides read stories, toggles previews, and marks
  everything read.
- **Reading** – on iOS stories open in a full-screen Safari view (Reader mode
  optional). Hacker News and Memeorandum stories also carry a link to their
  discussion, reachable from the long-press menu or the Article/Comments toggle
  on macOS. Settings can send links to the system browser instead.
- **Saved** – a reading list that persists across launches.
- **Search** – searches every fetched story, not just the front page, plus the
  saved list.
- **Settings** – switch built-in sources on or off, manage RSS feeds (with OPML
  import and export), and clear history. On the Mac it opens in its own
  window (⌘,).
- **iPad and Mac** – the tabs become a sidebar, and Today splits in two: a
  rail with the date and Top of the Stack, beside a story column that stays
  a comfortable width. Saved, Search, and Settings keep a centered column
  instead of stretching across the window. A Feed menu adds
  ⌘R to refresh, ⌘1–⌘5 to pick a source, and ⇧⌘H to hide read stories; the
  same shortcuts work from an iPad keyboard. iPhone layouts are unchanged.

## Design: Stone & Paper

The interface takes its cues from the app icon, three granite stones balanced
on warm paper.

- **Paper and ink.** Warm paper backgrounds, ink text, and hairline dividers.
  The only accent is a muted moss. Each source gets a mineral tint (rust,
  slate, verdigris, heather), shown as a small pebble next to its name.
- **Type.** Headlines are set in New York, the system serif. Source names and
  section labels are small tracked capitals.
- **The stack.** Top of the Stack draws its stories as stones: one width,
  thicker toward the base, graded light to dark like the icon. Only these
  stones carry the icon's granite grain (the `StoneGrain` tile, at 30%). Rows
  stay clean.
- **Cairns as signals.** A story that appears in several places gets a small
  cairn, one stone per source. Empty, loading, and caught-up states use a drawn
  version of the icon.

Colors live in `Assets.xcassets/Palette` with light and dark variants. Tokens
and shared components are in `Design/`.

## Ranking

Today is built by **fair share**, so every source you have on is seen, not
just the busiest. The ranking knows nothing about particular sources. Each
story carries its **channel** (the feed it came from: Hacker News, STAT, one of
your RSS feeds) and whether that channel publishes its own order.

- **Standing** – how strongly a story stands on its own channel, from 0 to 1.
  A ranked page (Hacker News, Memeorandum) is judged by position on a page of
  30, whatever its fetch size. A newest-first feed (journals, blogs) is judged
  by freshness on its own clock: it halves every twice the feed's typical gap
  between posts, from 3 to 24 hours, counted from the feed's own newest story
  (up to a day behind is forgiven, for feeds that post in batches or date by
  day). So a weekly blog and a wire feed are each judged by their own rhythm.
- **Fresh enough** – newest-first stories stay in Today while their standing
  is at least 0.35 and they are under 36 hours old; older ones stay in their
  source's tab. Ranked pages decide for themselves.
- **Cross-posting** – a story carried by several sources gains 0.25 standing
  per extra source. Stories are matched across each source's whole fetch by
  normalized link (scheme, `www.`/mobile/AMP variants, fragments, tracking and
  gift-link parameters are ignored), by the other outlets Memeorandum lists
  for a story, and by headlines that share most of their words.
- **Fair share** – each position goes to the source furthest below its share
  of the list so far, which takes its best remaining story; its channels take
  turns the same way. A source of ranked pages gets twice the share of a
  newest-first one, since it has already chosen what matters. A source with
  nothing fresh gives up its turn. Ranked pages keep their own order.

`Tools/FeedLab` replays real days through this code; its `FINDINGS.md` has the
measurements behind the design.

Stories that arrived since your last visit (a gap of five minutes or more)
sit above an **Earlier** line, so you can see where you left off.

## Reading signals

To try personalized ranking later, Grindstone keeps a private log on the
device of what comes on screen, what you open and for how long, and what you
save, skip, or mark read, with each story's source, site, position, and score
at the time. It lives in Application Support as `engagement.jsonl`
(`EngagementLog`), trims itself past 8 MB, and can be cleared in Settings. It
does not affect ranking yet.

## How it fits together

| Layer | Files |
| --- | --- |
| Models | `FeedItem`, `Source`, `ArticleDestination` |
| Fetching | one service per source under `Services/`, coordinated by `FeedSourceCatalog` |
| Ranking | `CrossRefEngine` groups the same story across sources; `FeedRankingEngine` blends placement, cross-references, and recency |
| State | `FeedViewModel` (feed), `FeedUserStateStore` (read/saved), `FeedPreferences` (settings), `ManualRSSFeedStore` (RSS library), `ReadingSessionStore` (visits and story arrivals), `EngagementLog` (reading signals) |
| Design | `Theme` (palette, type, row styles, pebble button), `Stone` (stone tones, grained surface, cairn mark and glyph), `Components` (section labels, empty states) |
| UI | `RootView` tab layout, `FeedView`, `FilterBar`, `StoneStack`, `FeedItemRow`, `StoryParts`, `SettingsView`, `RSSFeedManagerView`, `SearchView`, `SavedArticlesView` |

Feeds are cached to Application Support so the app opens with the last
snapshot before refreshing. Coming back to the app refreshes again once the
feed is more than 15 minutes old. Requires iOS 26 / macOS 26.
