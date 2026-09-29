#!/usr/bin/env python3
"""Collects snapshots of Grindstone's sources for replay.

Two kinds of snapshot:

  live      Exactly what the app would fetch right now: HN's topstories and
            item JSON, memeorandum's homepage and feed.xml, bioRxiv and arXiv
            with the app's own queries and dates, and the STAT, Nature and
            Marginal Revolution feeds. Nothing is reconstructed.

  history   Past moments, rebuilt from what the sources still serve:
            - Hacker News: its per-day archive (front?day=), ranked at the
              snapshot time with HN's published gravity formula. Final point
              counts stand in for the counts at the time; `live` records how
              close this reconstruction comes to the real front page.
            - bioRxiv and arXiv: the APIs, bounded to the snapshot time.
            - STAT, Nature, Marginal Revolution: the live feeds with later
              entries removed. Feeds only reach back a day or three, so older
              snapshots note when a feed no longer covers them.
            - Memeorandum: its archive pages are blocked (Cloudflare) and its
              feed holds only the newest hour, so history snapshots replay with
              Memeorandum switched off, a setting the app offers.

Usage:
  collect.py live [--out DIR]
  collect.py history --days 2026-09-22 ... --times 13:00 21:00 [--out DIR]
  collect.py upgrade [--out DIR]    bring older snapshots up to date

Times are US Eastern. Only the standard library is used.
"""

import argparse
import datetime as dt
import email.utils
import hashlib
import html
import json
import math
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
USER_AGENT = "GrindstoneFeedLab/1.0 (feed ranking research)"
REQUEST_PAUSE = 0.5
HN_LANE = 60  # HNService.fetch(limit: 60)

FEEDS = {
    "www.statnews.com/feed/": "https://www.statnews.com/feed/",
    # The subject feed the app read before switching to the journal's own.
    "www.nature.com/subjects/biotechnology.rss": "https://www.nature.com/subjects/biotechnology.rss",
    "www.nature.com/nbt.rss": "https://www.nature.com/nbt.rss",
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
        # A readable prefix plus a hash of the whole URL: long URLs (arXiv
        # queries) differ only near the end, where a plain prefix is cut off.
        digest = hashlib.sha1(url.encode()).hexdigest()[:16]
        key = re.sub(r"[^A-Za-z0-9._-]+", "_", url)[:150] + "_" + digest
        path = os.path.join(self.cache_dir, key)
        if use_cache and os.path.exists(path):
            with open(path, "rb") as f:
                return f.read()
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
                if use_cache:
                    with open(path, "wb") as f:
                        f.write(body)
                return body
            except urllib.error.HTTPError as error:
                last_error = error
                if error.code in (403, 404):
                    break
            except Exception as error:
                last_error = error
            time.sleep(2 ** (attempt + 1))
        raise RuntimeError(f"GET {url} failed: {last_error}")


# MARK: - Hacker News

def parse_hn_page(page_html):
    """Stories on an HN listing page, in order."""
    stories = []
    rows = re.finditer(
        r"<tr[^>]*class=['\"]athing[^'\"]*['\"][^>]*id=['\"](\d+)['\"][^>]*>(.*?)</tr>\s*<tr[^>]*>(.*?)</tr>",
        page_html,
        re.S,
    )
    for row in rows:
        item_id, head, sub = int(row.group(1)), row.group(2), row.group(3)
        link = re.search(r'<span class="titleline"[^>]*>\s*<a href="([^"]+)"[^>]*>(.*?)</a>', head, re.S)
        if not link:
            continue
        href = html.unescape(link.group(1))
        score = re.search(r'class="score"[^>]*>(\d+)\s+point', sub)
        age = re.search(r'class="age"[^>]*title="([^"]+)"', sub)
        comments = re.search(r">(\d+)(?:&nbsp;|\s)+comments?</a>", sub)
        posted = None
        if age:
            parts = age.group(1).split()
            if len(parts) > 1 and parts[1].isdigit():
                posted = int(parts[1])
            else:
                posted = int(dt.datetime.fromisoformat(parts[0]).replace(tzinfo=UTC).timestamp())
        is_job = score is None and "hnuser" not in sub
        stories.append(
            {
                "id": item_id,
                "type": "job" if is_job else "story",
                "title": html.unescape(re.sub(r"<[^>]+>", "", link.group(2))).strip(),
                "url": None if href.startswith("item?id=") else urllib.parse.urljoin("https://news.ycombinator.com/", href),
                "score": int(score.group(1)) if score else None,
                "descendants": int(comments.group(1)) if comments else (None if is_job else 0),
                "time": posted,
            }
        )
    return stories


def hn_day(fetcher, day, pages=3):
    stories, seen = [], set()
    for page in range(1, pages + 1):
        body = fetcher.get(f"https://news.ycombinator.com/front?day={day}&p={page}", use_cache=day < dt.date.today())
        for story in parse_hn_page(body.decode("utf-8", "replace")):
            if story["id"] not in seen:
                seen.add(story["id"])
                stories.append(story)
    return stories


def hn_gravity_rank(stories, moment):
    """HN's published ranking, (points - 1)^0.8 / (age + 2)^1.8, at `moment`."""
    now = moment.timestamp()
    ranked = []
    for story in stories:
        if story["type"] != "story" or story["time"] is None or story["time"] > now:
            continue
        age_hours = (now - story["time"]) / 3600
        if age_hours > 48:
            continue
        points = max((story["score"] or 1) - 1, 0)
        ranked.append((points ** 0.8 / (age_hours + 2) ** 1.8, story))
    ranked.sort(key=lambda pair: -pair[0])
    return [story for _, story in ranked]


def write_hn(files, stories):
    files["hacker-news.firebaseio.com/v0/topstories.json"] = json.dumps([s["id"] for s in stories])
    for story in stories:
        files[f"hacker-news.firebaseio.com/v0/item/{story['id']}.json"] = json.dumps(
            {k: v for k, v in story.items() if v is not None}
        )


def hn_history(fetcher, moment, files, notes):
    local_day = moment.astimezone(UTC).date()
    pool = {}
    for day in (local_day - dt.timedelta(days=1), local_day):
        for story in hn_day(fetcher, day):
            pool.setdefault(story["id"], story)
    ranked = hn_gravity_rank(pool.values(), moment)[:HN_LANE]
    write_hn(files, ranked)
    notes.append(f"Hacker News: reconstructed from front?day archives ({len(pool)} candidates), "
                 f"top {len(ranked)} by HN gravity at the snapshot using final points")


def hn_live(fetcher, files, notes, analysis):
    ids = json.loads(fetcher.get("https://hacker-news.firebaseio.com/v0/topstories.json", use_cache=False))
    files["hacker-news.firebaseio.com/v0/topstories.json"] = json.dumps(ids[:HN_LANE])
    live = []
    for item_id in ids[:HN_LANE]:
        body = fetcher.get(f"https://hacker-news.firebaseio.com/v0/item/{item_id}.json", use_cache=False)
        files[f"hacker-news.firebaseio.com/v0/item/{item_id}.json"] = body.decode()
        live.append(json.loads(body))
    notes.append(f"Hacker News: live topstories, {len(live)} items")

    # How well does the history reconstruction match the real front page?
    now = dt.datetime.now(UTC)
    pool = {}
    for day in (now.date() - dt.timedelta(days=1), now.date()):
        for story in hn_day(fetcher, day):
            pool.setdefault(story["id"], story)
    for item in live:  # the per-day archive can lag; include live items with current points
        if item and item.get("type") == "story":
            pool.setdefault(item["id"], {"id": item["id"], "type": "story", "score": item.get("score"), "time": item.get("time")})
    rebuilt = [s["id"] for s in hn_gravity_rank(pool.values(), now)[:HN_LANE]]
    real = [i for i in ids[:HN_LANE]]
    overlap20 = len(set(rebuilt[:20]) & set(real[:20]))
    common = [i for i in real[:30] if i in rebuilt]
    positions = [rebuilt.index(i) for i in common]
    concordant = sum(1 for a in range(len(positions)) for b in range(a + 1, len(positions)) if positions[a] < positions[b])
    pairs = len(positions) * (len(positions) - 1) // 2
    tau = (2 * concordant - pairs) / pairs if pairs else float("nan")
    analysis["hn_reconstruction"] = {"top20_overlap": overlap20, "kendall_tau_top30": tau}
    notes.append(f"Hacker News reconstruction check: rebuilt top 20 shares {overlap20}/20 with the real one; "
                 f"order agreement (Kendall τ over real top 30) {tau:.2f}")


# MARK: - Memeorandum

def memo_live(fetcher, files, notes, analysis):
    homepage = fetcher.get("https://www.memeorandum.com/", use_cache=False).decode("utf-8", "replace")
    feed = fetcher.get("https://www.memeorandum.com/feed.xml", use_cache=False).decode("utf-8", "replace")
    files["www.memeorandum.com/"] = homepage
    files["www.memeorandum.com/feed.xml"] = feed
    marker = homepage.find('<SPAN CLASS="rnhd2">Top Items:</SPAN>')
    top_ids = re.findall(r'<DIV CLASS="item" ID="([^"]+)"', homepage[marker:]) if marker >= 0 else []
    feed_ids = set(re.findall(r"#a(\d{6}p\d+)", feed)) | {
        a + b for a, b in re.findall(r"memeorandum\.com/(\d{6})/(p\d+)", feed)
    }
    covered = sum(1 for i in top_ids if i in feed_ids)
    analysis["memo_feed_coverage"] = {"top_items": len(top_ids), "in_feed": covered}
    notes.append(f"Memeorandum: live homepage ({len(top_ids)} top items); feed.xml covers {covered} of them")


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


WORDPRESS_FEEDS = {"www.statnews.com/feed/", "marginalrevolution.com/feed"}


def wordpress_feed_at(fetcher, url, moment, pages=12):
    """The feed as it stood at `moment`: WordPress serves older entries with
    ?paged=N, so the newest page-one-sized set published by then is rebuilt."""
    first = fetcher.get(url).decode("utf-8", "replace")
    page_size = len(ITEM_BLOCK.findall(first))
    entries, seen = [], set()
    for page in range(1, pages + 1):
        body = first if page == 1 else fetcher.get(f"{url}?paged={page}").decode("utf-8", "replace")
        blocks = ITEM_BLOCK.findall(body)
        for block in blocks:
            link = re.search(r"<link>(.*?)</link>", block, re.S)
            date = DATE_TAG.search(block)
            published = parse_feed_date(date.group(2)) if date else None
            key = link.group(1).strip() if link else block[:200]
            if published and key not in seen:
                seen.add(key)
                entries.append((published, block))
        if not blocks or min(p for p, _ in entries) < moment - dt.timedelta(days=3):
            break
    chosen = sorted((e for e in entries if e[0] <= moment), key=lambda e: e[0], reverse=True)[:page_size]
    head = first[: first.find(ITEM_BLOCK.search(first).group(0))] if ITEM_BLOCK.search(first) else first
    tail = first[first.rfind("</channel>"):] if "</channel>" in first else ""
    xml = head + "".join(block for _, block in chosen) + tail
    return xml, len(chosen), (chosen[-1][0] if chosen else None)


def feeds(fetcher, moment, files, notes, *, live):
    for key, url in FEEDS.items():
        body = fetcher.get(url, use_cache=not live).decode("utf-8", "replace")
        if live:
            files[key] = body
            continue
        if key in WORDPRESS_FEEDS:
            xml, kept, oldest = wordpress_feed_at(fetcher, url, moment)
            files[key] = xml
            notes.append(f"{key}: rebuilt as of the snapshot from its paged archive, {kept} entries"
                         + (f" back to {oldest:%Y-%m-%d %H:%M}Z" if oldest else ""))
            continue
        xml, kept, removed, oldest = trim_feed(body, moment)
        files[key] = xml
        partial = oldest is None or (moment - oldest) < dt.timedelta(hours=24)
        notes.append(f"{key}: live feed trimmed to the snapshot, {kept} entries"
                     + (f" back to {oldest:%Y-%m-%d %H:%M}Z" if oldest else "")
                     + (" (PARTIAL: the feed no longer reaches a day before this snapshot)" if partial else ""))


# MARK: - bioRxiv and arXiv

def biorxiv(fetcher, moment, files, notes, analysis, *, live):
    end = moment.astimezone(UTC).date()
    start = end - dt.timedelta(days=7)
    for category in BIORXIV_CATEGORIES:
        first_url = f"https://api.biorxiv.org/details/biorxiv/{start}/{end}/0/json?category={category}"
        body = fetcher.get(first_url, use_cache=not live)
        files[f"biorxiv/{category}/0"] = body.decode("utf-8", "replace")
        first = json.loads(body)
        total = int(first.get("messages", [{}])[0].get("total", 0) or 0)
        save_biorxiv_newest_page(fetcher, files, category, start, end, first, use_cache=not live)
        records = list(first.get("collection", []))
        cursor = len(records)
        while cursor < total:
            page = json.loads(fetcher.get(
                f"https://api.biorxiv.org/details/biorxiv/{start}/{end}/{cursor}/json?category={category}",
                use_cache=not live,
            )).get("collection", [])
            if not page:
                break
            records += page
            cursor += len(page)
        first_dates = sorted({r["date"] for r in first.get("collection", [])})
        all_dates = sorted({r["date"] for r in records})
        analysis[f"biorxiv/{category}"] = {
            "total": total,
            "first_page_dates": first_dates,
            "all_dates": all_dates,
            "category_matches": sum(1 for r in first.get("collection", []) if r.get("category", "").lower() == category),
        }
        notes.append(f"bioRxiv/{category}: {total} records {start}..{end}; the app reads the first "
                     f"{len(first.get('collection', []))}, dated {first_dates[0] if first_dates else '?'}.."
                     f"{first_dates[-1] if first_dates else '?'}")


def save_biorxiv_newest_page(fetcher, files, category, start, end, first, *, use_cache=True):
    """The page the app asks for after the first: the window's last `count`
    records (cursor = total - count), which are the newest."""
    total = int(first.get("messages", [{}])[0].get("total", 0) or 0)
    count = len(first.get("collection", []))
    if count and total > count:
        cursor = total - count
        url = f"https://api.biorxiv.org/details/biorxiv/{start}/{end}/{cursor}/json?category={category}"
        files[f"biorxiv/{category}/{cursor}"] = fetcher.get(url, use_cache=use_cache).decode("utf-8", "replace")


def upgrade(fetcher, out_dir):
    """Brings snapshots collected before the app read bioRxiv's newest page and
    Nature Biotechnology's own feed up to date, so old and new code replay the
    same data: bioRxiv page 0 moves to its per-page key, the newest page is
    fetched for the same window, and the journal feed is added, trimmed to the
    snapshot."""
    for path in sorted(os.listdir(out_dir)):
        meta_path = os.path.join(out_dir, path, "snapshot.json")
        if not os.path.exists(meta_path):
            continue
        meta = json.load(open(meta_path))
        moment = dt.datetime.fromisoformat(meta["time"])
        files = {}
        for key, name in list(meta["files"].items()):
            if key.startswith("biorxiv/") and key.count("/") == 1:
                files[key + "/0"] = open(os.path.join(out_dir, path, name), encoding="utf-8").read()
                del meta["files"][key]
        for key, name in meta["files"].items():
            if key.startswith("biorxiv/") and key.endswith("/0"):
                files.setdefault(key, open(os.path.join(out_dir, path, name), encoding="utf-8").read())
        end = moment.astimezone(UTC).date()
        start = end - dt.timedelta(days=7)
        for key in [k for k in files if k.startswith("biorxiv/")]:
            category = key.split("/")[1]
            save_biorxiv_newest_page(fetcher, files, category, start, end, json.loads(files[key]))
        if "www.nature.com/nbt.rss" not in meta["files"]:
            xml, kept, _, _ = trim_feed(fetcher.get(FEEDS["www.nature.com/nbt.rss"]).decode("utf-8", "replace"), moment)
            files["www.nature.com/nbt.rss"] = xml
            meta["notes"].append(f"www.nature.com/nbt.rss: added later from the live feed, {kept} entries before the snapshot")
        for key, content in files.items():
            name = re.sub(r"[^A-Za-z0-9._-]+", "_", key)
            with open(os.path.join(out_dir, path, name), "w", encoding="utf-8") as f:
                f.write(content)
            meta["files"][key] = name
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)
        print(f"upgraded {path}: " + ", ".join(sorted(k for k in files if k.startswith("biorxiv/") or "nbt" in k)))


def arxiv(fetcher, moment, files, notes, *, live):
    params = {"search_query": ARXIV_QUERY, "start": 0, "max_results": ARXIV_MAX_RESULTS,
              "sortBy": "submittedDate", "sortOrder": "descending"}
    if not live:
        end = moment.astimezone(UTC)
        params["search_query"] = f"({ARXIV_QUERY}) AND submittedDate:[{end - dt.timedelta(days=30):%Y%m%d%H%M} TO {end:%Y%m%d%H%M}]"
    body = fetcher.get("https://export.arxiv.org/api/query?" + urllib.parse.urlencode(params), use_cache=not live)
    files["arxiv"] = body.decode("utf-8", "replace")
    notes.append(f"arXiv: {body.count(b'<entry>')} entries")


# MARK: - Driver

def write_snapshot(out_dir, snapshot_id, moment, files, notes, analysis, disabled=()):
    directory = os.path.join(out_dir, snapshot_id)
    os.makedirs(directory, exist_ok=True)
    manifest = {}
    for key, content in files.items():
        name = re.sub(r"[^A-Za-z0-9._-]+", "_", key)
        with open(os.path.join(directory, name), "w", encoding="utf-8") as f:
            f.write(content)
        manifest[key] = name
    with open(os.path.join(directory, "snapshot.json"), "w") as f:
        json.dump({"id": snapshot_id, "time": moment.astimezone(UTC).isoformat(timespec="seconds"),
                   "notes": notes, "files": manifest, "analysis": analysis,
                   "disabledSources": list(disabled)}, f, indent=2)


def run_steps(steps, notes):
    for name, step in steps:
        try:
            step()
        except Exception as error:
            notes.append(f"{name}: FAILED ({error})")
            print(f"   {name} failed: {error}", file=sys.stderr, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["live", "history", "upgrade"])
    parser.add_argument("--days", nargs="*", default=[])
    parser.add_argument("--times", nargs="*", default=["13:00", "21:00"])
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
    args = parser.parse_args()
    fetcher = Fetcher(os.path.join(args.out, ".cache"))

    if args.mode == "upgrade":
        upgrade(fetcher, args.out)
        return

    if args.mode == "live":
        moment = dt.datetime.now(UTC).replace(microsecond=0)
        files, notes, analysis = {}, [], {}
        run_steps([
            ("Hacker News", lambda: hn_live(fetcher, files, notes, analysis)),
            ("Memeorandum", lambda: memo_live(fetcher, files, notes, analysis)),
            ("feeds", lambda: feeds(fetcher, moment, files, notes, live=True)),
            ("bioRxiv", lambda: biorxiv(fetcher, moment, files, notes, analysis, live=True)),
            ("arXiv", lambda: arxiv(fetcher, moment, files, notes, live=True)),
        ], notes)
        snapshot_id = "live_" + moment.astimezone(EASTERN).strftime("%Y-%m-%d_%H%M")
        write_snapshot(args.out, snapshot_id, moment, files, notes, analysis)
        print(f"== {snapshot_id}\n   " + "\n   ".join(notes))
        return

    for day in args.days:
        for clock in args.times:
            moment = dt.datetime.combine(dt.date.fromisoformat(day), dt.time.fromisoformat(clock), tzinfo=EASTERN)
            files, notes, analysis = {}, [], {}
            notes.append("Memeorandum: switched off (no archive access)")
            run_steps([
                ("Hacker News", lambda: hn_history(fetcher, moment, files, notes)),
                ("feeds", lambda: feeds(fetcher, moment, files, notes, live=False)),
                ("bioRxiv", lambda: biorxiv(fetcher, moment, files, notes, analysis, live=False)),
                ("arXiv", lambda: arxiv(fetcher, moment, files, notes, live=False)),
            ], notes)
            snapshot_id = "hist_" + moment.strftime("%Y-%m-%d_%H%M")
            write_snapshot(args.out, snapshot_id, moment, files, notes, analysis, disabled=["Memeorandum"])
            print(f"== {snapshot_id}\n   " + "\n   ".join(notes), flush=True)


if __name__ == "__main__":
    main()
