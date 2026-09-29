#!/usr/bin/env python3
"""Collects what Grindstone's sources looked like at past moments.

For each snapshot time it saves the responses the app would have received,
keyed the way `replay/ReplayNetworking.swift` looks them up, so the app's own
services, merging, and ranking can be replayed over them:

  Hacker News    Wayback Machine capture of the front page (and page 2 when
                 archived), turned into the topstories.json / item JSON the
                 app requests.
  Memeorandum    memeorandum's own archive page for that time. Its RSS feed
                 isn't archived, so a stand-in feed.xml carries each story's
                 first appearance in the hourly archives as its date.
  bioRxiv        The API, over the week up to the snapshot's day (cursor 0,
                 exactly as the app asks), plus every page for analysis.
  arXiv          The API, with the app's query limited to submissions before
                 the snapshot.
  STAT, Nature,  Wayback capture of the feed nearest the snapshot, else the
  Marginal Rev.  live feed, with entries published after the snapshot removed.

Usage:
  collect.py --days 2026-09-25 2026-09-26 --times 08:00 13:00 18:00 22:00 \
      --out Tools/FeedLab/data

Times are US Eastern (memeorandum's clock). Only the standard library is used.
"""

import argparse
import datetime as dt
import email.utils
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")
UTC = dt.timezone.utc
USER_AGENT = "GrindstoneFeedLab/1.0 (feed ranking research; polite, cached)"
REQUEST_PAUSE = 1.0

FEEDS = {
    "www.statnews.com/feed/": "https://www.statnews.com/feed/",
    "www.nature.com/subjects/biotechnology.rss": "https://www.nature.com/subjects/biotechnology.rss",
    "marginalrevolution.com/feed": "https://marginalrevolution.com/feed",
}
BIORXIV_CATEGORIES = ["bioengineering", "genetics", "genomics"]
ARXIV_QBIO = ["q-bio.BM", "q-bio.CB", "q-bio.GN", "q-bio.MN", "q-bio.QM", "q-bio.SC", "q-bio.TO"]
# Must match ArXivBiotechService.searchQuery.
ARXIV_QUERY = " OR ".join(
    f"({part})"
    for part in [
        " OR ".join(f"cat:{c}" for c in ARXIV_QBIO),
        "(cat:cs.LG AND (all:biology OR all:biological OR all:bioinformatics OR all:genomics "
        "OR all:protein OR all:proteomics OR all:drug OR all:cell OR all:gene OR all:biomedical))",
    ]
)
ARXIV_MAX_RESULTS = 20  # max(limit * 2, 18) with limit 10


# MARK: - HTTP

class Fetcher:
    def __init__(self, cache_dir):
        self.cache_dir = cache_dir
        os.makedirs(cache_dir, exist_ok=True)
        self.last_request = 0.0

    def get(self, url, *, use_cache=True):
        """Returns (final_url, bytes). Raises on HTTP errors after retries."""
        key = re.sub(r"[^A-Za-z0-9._-]+", "_", url)[:200]
        body_path = os.path.join(self.cache_dir, key)
        meta_path = body_path + ".url"
        if use_cache and os.path.exists(body_path) and os.path.exists(meta_path):
            with open(body_path, "rb") as f, open(meta_path) as m:
                return m.read().strip(), f.read()

        last_error = None
        for attempt in range(4):
            wait = self.last_request + REQUEST_PAUSE - time.time()
            if wait > 0:
                time.sleep(wait)
            self.last_request = time.time()
            try:
                request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=60) as response:
                    body = response.read()
                    final_url = response.geturl()
                with open(body_path, "wb") as f:
                    f.write(body)
                with open(meta_path, "w") as m:
                    m.write(final_url)
                return final_url, body
            except urllib.error.HTTPError as error:
                last_error = error
                if error.code in (404, 403):
                    break
            except Exception as error:  # network hiccup
                last_error = error
            time.sleep(2 ** (attempt + 1))
        raise RuntimeError(f"GET {url} failed: {last_error}")


def wayback(fetcher, url, moment):
    """Nearest Wayback capture of `url` to `moment`. Returns (capture_time, bytes)."""
    stamp = moment.astimezone(UTC).strftime("%Y%m%d%H%M%S")
    final_url, body = fetcher.get(f"https://web.archive.org/web/{stamp}id_/{url}")
    match = re.search(r"/web/(\d{14})", final_url)
    captured = (
        dt.datetime.strptime(match.group(1), "%Y%m%d%H%M%S").replace(tzinfo=UTC) if match else None
    )
    return captured, body


# MARK: - Hacker News

def parse_hn_page(page_html, rank_offset=0):
    """Stories on an archived HN listing page, in order."""
    stories = []
    rows = re.finditer(
        r"<tr[^>]*class=['\"]athing[^'\"]*['\"][^>]*id=['\"](\d+)['\"][^>]*>(.*?)</tr>\s*<tr[^>]*>(.*?)</tr>",
        page_html,
        re.S,
    )
    for index, row in enumerate(rows):
        item_id, head, sub = int(row.group(1)), row.group(2), row.group(3)
        link = re.search(r'<span class="titleline"[^>]*>\s*<a href="([^"]+)"[^>]*>(.*?)</a>', head, re.S) or re.search(
            r'<a href="([^"]+)"[^>]*class="(?:storylink|titlelink)"[^>]*>(.*?)</a>', head, re.S
        )
        if not link:
            continue
        href = html.unescape(link.group(1))
        title = html.unescape(re.sub(r"<[^>]+>", "", link.group(2))).strip()
        score = re.search(r'class="score"[^>]*>(\d+)\s+point', sub)
        age = re.search(r'class="age"[^>]*title="([^"]+)"', sub)
        comments = re.search(r">(\d+)(?:&nbsp;|\s)+comments?</a>", sub)
        posted = None
        if age:
            parts = age.group(1).split()
            if len(parts) > 1 and parts[1].isdigit():
                posted = int(parts[1])
            else:
                try:
                    posted = int(dt.datetime.fromisoformat(parts[0]).replace(tzinfo=UTC).timestamp())
                except ValueError:
                    posted = None
        is_job = score is None and "hnuser" not in sub
        stories.append(
            {
                "id": item_id,
                "rank": rank_offset + index + 1,
                "type": "job" if is_job else "story",
                "title": title,
                "url": None if href.startswith("item?id=") else urllib.parse.urljoin("https://news.ycombinator.com/", href),
                "score": int(score.group(1)) if score else None,
                "descendants": int(comments.group(1)) if comments else (0 if not is_job else None),
                "time": posted,
            }
        )
    return stories


def collect_hn(fetcher, moment, files, notes):
    captured, body = wayback(fetcher, "https://news.ycombinator.com/", moment)
    stories = parse_hn_page(body.decode("utf-8", "replace"))
    if not stories:
        notes.append("Hacker News: archived front page had no parseable stories")
        return
    offset_minutes = abs((captured - moment).total_seconds()) / 60 if captured else None
    notes.append(f"Hacker News: capture {captured.isoformat() if captured else '?'} "
                 f"({offset_minutes:.0f} min from snapshot), {len(stories)} stories on page 1")
    try:
        captured2, body2 = wayback(fetcher, "https://news.ycombinator.com/?p=2", moment)
        if captured2 and abs((captured2 - moment).total_seconds()) < 3 * 3600:
            more = parse_hn_page(body2.decode("utf-8", "replace"), rank_offset=len(stories))
            known = {s["id"] for s in stories}
            stories += [s for s in more if s["id"] not in known]
            notes.append(f"Hacker News: page 2 capture {captured2.isoformat()}, now {len(stories)} stories")
        else:
            notes.append("Hacker News: no page 2 capture within 3 hours; lane has page 1 only")
    except RuntimeError as error:
        notes.append(f"Hacker News: page 2 unavailable ({error})")

    files["hacker-news.firebaseio.com/v0/topstories.json"] = json.dumps([s["id"] for s in stories])
    for story in stories:
        item = {k: v for k, v in story.items() if k not in ("rank",) and v is not None}
        files[f"hacker-news.firebaseio.com/v0/item/{story['id']}.json"] = json.dumps(item)


# MARK: - Memeorandum

MEMO_ITEM_ID = re.compile(r'<DIV CLASS="item" ID="([^"]+)"')
MEMO_MARKER = '<SPAN CLASS="rnhd2">Top Items:</SPAN>'


def memo_archive(fetcher, moment):
    local = moment.astimezone(EASTERN)
    url = f"https://www.memeorandum.com/{local:%y%m%d}/h{local:%H%M}"
    _, body = fetcher.get(url)
    return url, body.decode("utf-8", "replace")


def memo_top_ids(page_html):
    start = page_html.find(MEMO_MARKER)
    if start < 0:
        return []
    return MEMO_ITEM_ID.findall(page_html[start:])


def memo_top_items(page_html):
    """(id, title) for each Top Items cluster lead, as the app's parser reads them."""
    start = page_html.find(MEMO_MARKER)
    if start < 0:
        return []
    items = []
    for cluster in page_html[start:].split('<DIV CLASS="clus">')[1:]:
        item_id = MEMO_ITEM_ID.search(cluster)
        title = re.search(r'<DIV CLASS="ii"><STRONG CLASS="L\d"><A HREF="[^"]+">(.*?)</A>', cluster, re.S)
        if item_id and title:
            items.append((item_id.group(1), html.unescape(re.sub(r"<[^>]+>", "", title.group(1))).strip()))
    return items


def collect_memo(fetcher, moment, first_seen, files, notes):
    url, page = memo_archive(fetcher, moment)
    items = memo_top_items(page)
    if not items:
        notes.append(f"Memeorandum: {url} had no Top Items; trying the Wayback Machine")
        captured, body = wayback(fetcher, "https://www.memeorandum.com/", moment)
        page = body.decode("utf-8", "replace")
        items = memo_top_items(page)
        notes.append(f"Memeorandum: Wayback capture {captured}, {len(items)} items")
    else:
        notes.append(f"Memeorandum: {url}, {len(items)} top items")
    files["www.memeorandum.com/"] = page

    # Stand-in RSS: the archive has no feed, so each item is dated by when it
    # first appeared in the hourly archives (an upper bound on when it was posted).
    entries = []
    undated = 0
    for item_id, title in items:
        seen = first_seen.get(item_id)
        if seen is None or seen > moment:
            seen = moment
            undated += 1
        permalink = f"https://www.memeorandum.com/{item_id[:6]}/{item_id[6:]}#a{item_id}"
        entries.append(
            f"<item><title>{html.escape(title)}</title><link>{html.escape(permalink)}</link>"
            f"<pubDate>{email.utils.format_datetime(seen.astimezone(UTC))}</pubDate></item>"
        )
    if undated:
        notes.append(f"Memeorandum: {undated} items not in earlier hourly archives, dated at the snapshot")
    files["www.memeorandum.com/feed.xml"] = (
        '<?xml version="1.0"?><rss version="2.0"><channel><title>memeorandum</title>'
        + "".join(entries)
        + "</channel></rss>"
    )


def memo_first_seen(fetcher, start, end, notes):
    """ID -> first hourly archive (Eastern) the item appears in, between start and end."""
    first_seen = {}
    moment = start.astimezone(EASTERN).replace(minute=0, second=0, microsecond=0)
    missing = 0
    while moment <= end:
        try:
            _, page = memo_archive(fetcher, moment)
            for item_id in memo_top_ids(page):
                first_seen.setdefault(item_id, moment)
        except RuntimeError:
            missing += 1
        moment += dt.timedelta(hours=1)
    if missing:
        notes.append(f"Memeorandum: {missing} hourly archives unavailable for first-seen dating")
    return first_seen


# MARK: - Feeds

ITEM_BLOCK = re.compile(r"<item\b.*?</item>|<entry\b.*?</entry>", re.S | re.I)
DATE_TAG = re.compile(r"<(pubDate|dc:date|published|updated)>(.*?)</\1>", re.S | re.I)


def parse_feed_date(text):
    text = html.unescape(text.strip())
    try:
        return email.utils.parsedate_to_datetime(text).astimezone(UTC)
    except (TypeError, ValueError):
        pass
    try:
        return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return None


def trim_feed(xml, moment):
    """Removes entries published after `moment`. Returns (xml, kept, removed, oldest)."""
    kept, removed, oldest = 0, 0, None

    def keep_or_drop(match):
        nonlocal kept, removed, oldest
        date_match = DATE_TAG.search(match.group(0))
        published = parse_feed_date(date_match.group(2)) if date_match else None
        if published and published > moment:
            removed += 1
            return ""
        kept += 1
        if published and (oldest is None or published < oldest):
            oldest = published
        return match.group(0)

    return ITEM_BLOCK.sub(keep_or_drop, xml), kept, removed, oldest


def collect_feeds(fetcher, moment, files, notes):
    for key, url in FEEDS.items():
        body, origin = None, None
        try:
            captured, body = wayback(fetcher, url, moment)
            if captured and abs((captured - moment).total_seconds()) <= 36 * 3600:
                origin = f"Wayback {captured.isoformat()}"
            else:
                body = None
        except RuntimeError:
            body = None
        if body is None:
            _, body = fetcher.get(url, use_cache=True)
            origin = "live feed"
        xml, kept, removed, oldest = trim_feed(body.decode("utf-8", "replace"), moment)
        notes.append(
            f"{key}: {origin}, kept {kept} entries (dropped {removed} newer), "
            f"oldest {oldest.isoformat() if oldest else '?'}"
        )
        files[key] = xml


# MARK: - bioRxiv and arXiv

def collect_biorxiv(fetcher, moment, files, notes, analysis):
    end = moment.astimezone(UTC).date()
    start = end - dt.timedelta(days=7)
    for category in BIORXIV_CATEGORIES:
        url = f"https://api.biorxiv.org/details/biorxiv/{start}/{end}/0/json?category={category}"
        _, body = fetcher.get(url)
        files[f"biorxiv/{category}"] = body.decode("utf-8", "replace")
        first = json.loads(body)
        total = int(first.get("messages", [{}])[0].get("total", 0) or 0)
        records = list(first.get("collection", []))
        cursor = len(records)
        while cursor < total:
            _, more = fetcher.get(
                f"https://api.biorxiv.org/details/biorxiv/{start}/{end}/{cursor}/json?category={category}"
            )
            page = json.loads(more).get("collection", [])
            if not page:
                break
            records += page
            cursor += len(page)
        analysis[f"biorxiv/{category}"] = {
            "total": total,
            "first_page_dates": sorted({r["date"] for r in first.get("collection", [])}),
            "all_dates": sorted({r["date"] for r in records}),
        }
        notes.append(f"bioRxiv/{category}: {total} records {start}..{end}; app reads the first "
                     f"{len(first.get('collection', []))}")


def collect_arxiv(fetcher, moment, files, notes):
    end = moment.astimezone(UTC)
    start = end - dt.timedelta(days=30)
    query = f"({ARXIV_QUERY}) AND submittedDate:[{start:%Y%m%d%H%M} TO {end:%Y%m%d%H%M}]"
    url = "https://export.arxiv.org/api/query?" + urllib.parse.urlencode(
        {
            "search_query": query,
            "start": 0,
            "max_results": ARXIV_MAX_RESULTS,
            "sortBy": "submittedDate",
            "sortOrder": "descending",
        }
    )
    _, body = fetcher.get(url)
    files["arxiv"] = body.decode("utf-8", "replace")
    notes.append(f"arXiv: {body.count(b'<entry>')} entries submitted before the snapshot")


# MARK: - Driver

def write_snapshot(out_dir, snapshot_id, moment, files, notes, analysis):
    directory = os.path.join(out_dir, snapshot_id)
    os.makedirs(directory, exist_ok=True)
    manifest = {}
    for key, content in files.items():
        name = re.sub(r"[^A-Za-z0-9._-]+", "_", key)
        with open(os.path.join(directory, name), "w", encoding="utf-8") as f:
            f.write(content)
        manifest[key] = name
    with open(os.path.join(directory, "snapshot.json"), "w") as f:
        json.dump(
            {
                "id": snapshot_id,
                "time": moment.astimezone(UTC).isoformat(),
                "notes": notes,
                "files": manifest,
                "analysis": analysis,
            },
            f,
            indent=2,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", nargs="+", required=True, help="YYYY-MM-DD, Eastern")
    parser.add_argument("--times", nargs="+", default=["08:00", "13:00", "18:00", "22:00"], help="HH:MM, Eastern")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "data"))
    args = parser.parse_args()

    moments = sorted(
        dt.datetime.combine(dt.date.fromisoformat(day), dt.time.fromisoformat(t), tzinfo=EASTERN)
        for day in args.days
        for t in args.times
    )
    fetcher = Fetcher(os.path.join(args.out, ".cache"))

    window_notes = []
    first_seen = memo_first_seen(fetcher, moments[0] - dt.timedelta(hours=36), moments[-1], window_notes)

    for moment in moments:
        snapshot_id = moment.strftime("%Y-%m-%d_%H%M")
        print(f"== {snapshot_id}", flush=True)
        files, notes, analysis = {}, list(window_notes), {}
        for name, step in [
            ("Hacker News", lambda: collect_hn(fetcher, moment, files, notes)),
            ("Memeorandum", lambda: collect_memo(fetcher, moment, first_seen, files, notes)),
            ("feeds", lambda: collect_feeds(fetcher, moment, files, notes)),
            ("bioRxiv", lambda: collect_biorxiv(fetcher, moment, files, notes, analysis)),
            ("arXiv", lambda: collect_arxiv(fetcher, moment, files, notes)),
        ]:
            try:
                step()
            except Exception as error:  # keep going; the replay reports the source as failed
                notes.append(f"{name}: FAILED ({error})")
                print(f"   {name} failed: {error}", file=sys.stderr, flush=True)
        write_snapshot(args.out, snapshot_id, moment, files, notes, analysis)
        for note in notes[len(window_notes):]:
            print("   " + note, flush=True)


if __name__ == "__main__":
    main()
