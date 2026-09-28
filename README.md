# Grindstone

A personal news aggregator for iPhone, iPad, and Mac. It pulls Hacker News,
Memeorandum, a set of biotech journals, and your own RSS feeds into one ranked
list, and flags stories that show up in more than one place.

## Using it

- **Today** – the merged front page. Tabs along the top filter by source.
  **Top of the Stack** sets the three stories that matter most as a cairn:
  cross-posted stories first, then the top story from each source. Below it,
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

## How it fits together

| Layer | Files |
| --- | --- |
| Models | `FeedItem`, `Source`, `ArticleDestination` |
| Fetching | one service per source under `Services/`, coordinated by `FeedSourceCatalog` |
| Ranking | `CrossRefEngine` finds the same URL across sources; `FeedRankingEngine` blends source rank, cross-references, and recency |
| State | `FeedViewModel` (feed), `FeedUserStateStore` (read/saved), `FeedPreferences` (settings), `ManualRSSFeedStore` (RSS library) |
| Design | `Theme` (palette, type, row styles, pebble button), `Stone` (stone tones, grained surface, cairn mark and glyph), `Components` (section labels, empty states) |
| UI | `RootView` tab layout, `FeedView`, `FilterBar`, `StoneStack`, `FeedItemRow`, `StoryParts`, `SettingsView`, `RSSFeedManagerView`, `SearchView`, `SavedArticlesView` |

Feeds are cached to Application Support so the app opens with the last
snapshot before refreshing. Requires iOS 26 / macOS 26.
