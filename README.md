# Grindstone

A personal news aggregator for iPhone, iPad, and Mac. It pulls Hacker News,
Memeorandum, a set of biotech journals, and your own RSS feeds into one ranked
list, and flags stories that show up in more than one place.

## Using it

- **Feed** – the merged front page. Chips filter by source. Swipe right to
  save, swipe left to mark read. The featured strip puts cross-posted stories
  first, then the top story from each source. The Options menu hides read
  stories, toggles previews, and marks everything read.
- **Reading** – on iOS stories open in a full-screen Safari view (Reader mode
  optional). Hacker News and Memeorandum stories also carry a link to their
  discussion, reachable from the long-press menu or the Article/Comments toggle
  on macOS. Settings can send links to the system browser instead.
- **Saved** – a reading list that persists across launches.
- **Search** – searches every fetched story, not just the front page, plus the
  saved list.
- **Settings** – switch built-in sources on or off, manage RSS feeds (with OPML
  import and export), and clear history.

## How it fits together

| Layer | Files |
| --- | --- |
| Models | `FeedItem`, `Source`, `ArticleDestination` |
| Fetching | one service per source under `Services/`, coordinated by `FeedSourceCatalog` |
| Ranking | `CrossRefEngine` finds the same URL across sources; `FeedRankingEngine` blends source rank, cross-references, and recency |
| State | `FeedViewModel` (feed), `FeedUserStateStore` (read/saved), `FeedPreferences` (settings), `ManualRSSFeedStore` (RSS library) |
| UI | `RootView` tab layout, `FeedView`, `FeedItemRow`, `FeaturedStrip`, `SettingsView`, `RSSFeedManagerView`, `SearchView`, `SavedArticlesView` |

Feeds are cached to Application Support so the app opens with the last
snapshot before refreshing. Requires iOS 26 / macOS 26.
