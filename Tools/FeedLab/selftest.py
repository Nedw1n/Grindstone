#!/usr/bin/env python3
"""Offline check of the collector and replay pipeline.

Runs collect.py's steps against canned responses shaped like the real
sources (HN's front page markup, memeorandum's cluster markup, WordPress and
RDF feeds, the bioRxiv and arXiv APIs) and writes snapshots to --out, which
run.sh can then replay. It proves the plumbing, not that the live pages still
look like this; collect.py's notes flag a page it can't parse.

  selftest.py --out Tools/FeedLab/build/selftest-data
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
import collect  # noqa: E402

UTC = dt.timezone.utc
DAY = dt.date(2026, 9, 28)


def et(hour, minute=0, day=DAY):
    return dt.datetime.combine(day, dt.time(hour, minute), tzinfo=collect.EASTERN)


# HN front page: (id, title, url or None, points, comments, posted)
HN_STORIES = [
    (45001, "The Fed holds rates steady and signals patience", "https://www.nytimes.com/2026/09/28/business/fed-rates.html?utm_source=hn", 512, 300, et(9)),
    (45002, "Show HN: A tiny Rust database", "https://github.com/someone/tinydb", 340, 88, et(7)),
    (45003, "Ask HN: What are you reading this fall?", None, 220, 410, et(6)),
    (45004, "YC startup Acme is hiring founding engineers", "https://acme.example/jobs", None, None, et(5)),
    (45005, "Senate passes sweeping AI chip export controls bill", "https://www.reuters.com/world/us/senate-ai-chips-2026-09-28/", 180, 120, et(11)),
    (45006, "CRISPR base editing reverses a rare liver disease in trial", "https://www.statnews.com/2026/09/28/base-editing-liver/", 95, 40, et(10)),
]

# memeorandum clusters: (id, title, url, outlet, related urls, first appears)
MEMO_ITEMS = [
    ("260928p10", "Fed holds rates steady, signals patience on cuts", "https://www.nytimes.com/2026/09/28/business/fed-rates.html", "New York Times",
     ["https://www.wsj.com/economy/fed-holds-rates", "https://x.com/someone/status/1"], et(9)),
    ("260928p11", "Senate passes AI chip export control bill in rare bipartisan vote", "https://www.washingtonpost.com/politics/2026/09/28/senate-chips/", "Washington Post",
     ["https://www.reuters.com/world/us/senate-ai-chips-2026-09-28/"], et(12)),
    ("260928p12", "Governor signs budget after marathon session", "https://apnews.com/article/budget-governor", "AP", [], et(8)),
    ("260927p40", "Supreme Court to hear major free speech case", "https://www.politico.com/news/2026/09/27/scotus-speech", "Politico", [], et(20, day=DAY - dt.timedelta(days=1))),
]


def hn_page(moment):
    rows = []
    for rank, (item_id, title, url, points, comments, posted) in enumerate(HN_STORIES, start=1):
        if posted > moment:
            continue
        href = url or f"item?id={item_id}"
        head = (f'<tr class="athing submission" id="{item_id}"><td align="right" valign="top" class="title">'
                f'<span class="rank">{rank}.</span></td><td class="title"><span class="titleline">'
                f'<a href="{href.replace("&", "&amp;")}">{title}</a></span></td></tr>')
        epoch = int(posted.timestamp())
        if points is None:
            sub = (f'<tr><td colspan="2"></td><td class="subtext"><span class="age" title="{posted.astimezone(UTC):%Y-%m-%dT%H:%M:%S} {epoch}">'
                   f'<a href="item?id={item_id}">1 hour ago</a></span></td></tr>')
        else:
            sub = (f'<tr><td colspan="2"></td><td class="subtext"><span class="subline"><span class="score" id="score_{item_id}">{points} points</span> '
                   f'by <a href="user?id=x" class="hnuser">x</a> <span class="age" title="{posted.astimezone(UTC):%Y-%m-%dT%H:%M:%S} {epoch}">'
                   f'<a href="item?id={item_id}">2 hours ago</a></span> | <a href="item?id={item_id}">{comments}&nbsp;comments</a></span></td></tr>')
        rows.append(head + sub + '<tr class="spacer" style="height:5px"></tr>')
    return "<html><body><table>" + "".join(rows) + "</table></body></html>"


def memo_page(moment):
    clusters = []
    for item_id, title, url, outlet, related, appears in MEMO_ITEMS:
        if appears > moment:
            continue
        links = "".join(f'<A HREF="{link}">more</A>' for link in related)
        clusters.append(
            f'<DIV CLASS="clus"><DIV CLASS="item" ID="{item_id}"><CITE>Jane Doe / <A HREF="https://{outlet.lower().replace(" ", "")}.example">{outlet}</A>:</CITE>'
            f'<DIV CLASS="ii"><STRONG CLASS="L3"><A HREF="{url}">{title}</A></STRONG> — A summary of the story.</DIV></DIV>'
            f'<DIV CLASS="dbpt">Discussion: {links}</DIV></DIV>'
        )
    return '<HTML><BODY><SPAN CLASS="rnhd2">Top Items:</SPAN>' + "".join(clusters) + "</BODY></HTML>"


def rss(items, rdf=False):
    blocks = []
    for title, link, published, extra in items:
        date = (f"<dc:date>{published.astimezone(UTC).isoformat()}</dc:date>" if rdf
                else f"<pubDate>{published.astimezone(UTC):%a, %d %b %Y %H:%M:%S +0000}</pubDate>")
        blocks.append(f"<item><title>{title}</title><link>{link}</link>{date}{extra}</item>")
    return '<?xml version="1.0"?><rss version="2.0"><channel><title>Feed</title>' + "".join(blocks) + "</channel></rss>"


FEED_BODIES = {
    "https://www.statnews.com/feed/": rss([
        ("Base editing reverses rare liver disease in first patients", "https://www.statnews.com/2026/09/28/base-editing-liver/", et(10),
         "<category><![CDATA[Biotech]]></category><description><![CDATA[<p>Trial results.</p>]]></description>"),
        ("FDA panel backs new obesity drug", "https://www.statnews.com/2026/09/28/fda-obesity/", et(16),
         "<category><![CDATA[Pharmaceuticals]]></category>"),
        ("Posted tonight: a late story", "https://www.statnews.com/2026/09/28/late/", et(23), ""),
    ]),
    "https://www.nature.com/subjects/biotechnology.rss": rss([
        ("Engineered enzymes for plastic recycling", "https://www.nature.com/articles/s41587-026-0001", et(4), ""),
    ], rdf=True),
    "https://marginalrevolution.com/feed": rss([
        ("Why did the Fed hold rates?", "https://marginalrevolution.com/marginalrevolution/2026/09/fed.html", et(12),
         "<description><![CDATA[Tyler on the decision.]]></description>"),
        ("Sunday assorted links", "https://marginalrevolution.com/marginalrevolution/2026/09/links.html", et(7, day=DAY - dt.timedelta(days=1)), ""),
    ]),
}


def biorxiv_body(url):
    parsed = urllib.parse.urlsplit(url)
    cursor = int(parsed.path.split("/")[5])
    category = urllib.parse.parse_qs(parsed.query)["category"][0]
    total = 150 if category == "genomics" else 40
    # Oldest first, like the API: the first page stops well short of the window's end.
    records = [
        {"title": f"{category.title()} preprint {n}", "doi": f"10.1101/2026.09.{n:03d}", "version": "1",
         "date": str(DAY - dt.timedelta(days=7) + dt.timedelta(days=n * 7 // total)), "category": category,
         "abstract": "An abstract."}
        for n in range(total)
    ][cursor:cursor + 100]
    return json.dumps({"messages": [{"status": "ok", "total": total, "count": len(records)}], "collection": records})


ARXIV_BODY = """<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>http://arxiv.org/abs/2609.00001v1</id><published>2026-09-27T17:00:00Z</published>
<title>Protein language models for enzyme design</title><summary>We study proteins.</summary>
<link href="http://arxiv.org/abs/2609.00001v1" rel="alternate" type="text/html"/>
<category term="q-bio.BM"/></entry></feed>"""


class CannedFetcher:
    def get(self, url, *, use_cache=True):
        wayback = re.match(r"https://web\.archive\.org/web/(\d{14})id_/(.*)", url)
        if wayback:
            moment = dt.datetime.strptime(wayback.group(1), "%Y%m%d%H%M%S").replace(tzinfo=UTC)
            captured = moment - dt.timedelta(minutes=7)
            final = f"https://web.archive.org/web/{captured:%Y%m%d%H%M%S}id_/{wayback.group(2)}"
            target = wayback.group(2)
            if target == "https://news.ycombinator.com/":
                return final, hn_page(captured).encode()
            if target in FEED_BODIES:
                return final, FEED_BODIES[target].encode()
            raise RuntimeError(f"no capture of {target}")
        memo = re.match(r"https://www\.memeorandum\.com/(\d{6})/h(\d{2})(\d{2})$", url)
        if memo:
            moment = dt.datetime.strptime(memo.group(1) + memo.group(2) + memo.group(3), "%y%m%d%H%M").replace(tzinfo=collect.EASTERN)
            return url, memo_page(moment).encode()
        if url.startswith("https://api.biorxiv.org/"):
            return url, biorxiv_body(url).encode()
        if url.startswith("https://export.arxiv.org/"):
            assert "submittedDate" in urllib.parse.unquote_plus(url)
            return url, ARXIV_BODY.encode()
        if url in FEED_BODIES:
            return url, FEED_BODIES[url].encode()
        raise RuntimeError(f"no canned response for {url}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    fetcher = CannedFetcher()
    moments = [et(13), et(18)]
    window_notes = []
    first_seen = collect.memo_first_seen(fetcher, moments[0] - dt.timedelta(hours=36), moments[-1], window_notes)
    assert first_seen["260928p11"] == et(12), first_seen["260928p11"]
    assert first_seen["260927p40"] <= et(20, day=DAY - dt.timedelta(days=1)) + dt.timedelta(hours=1)

    for moment in moments:
        files, notes, analysis = {}, list(window_notes), {}
        collect.collect_hn(fetcher, moment, files, notes)
        collect.collect_memo(fetcher, moment, first_seen, files, notes)
        collect.collect_feeds(fetcher, moment, files, notes)
        collect.collect_biorxiv(fetcher, moment, files, notes, analysis)
        collect.collect_arxiv(fetcher, moment, files, notes)
        collect.write_snapshot(args.out, moment.strftime("%Y-%m-%d_%H%M"), moment, files, notes, analysis)

        # Spot checks on what was written.
        top = json.loads(files["hacker-news.firebaseio.com/v0/topstories.json"])
        assert top[:3] == [45001, 45002, 45003], top
        ask = json.loads(files["hacker-news.firebaseio.com/v0/item/45003.json"])
        assert "url" not in ask and ask["score"] == 220 and ask["descendants"] == 410, ask
        job = json.loads(files["hacker-news.firebaseio.com/v0/item/45004.json"])
        assert job["type"] == "job", job
        assert "late story" not in files["www.statnews.com/feed/"], "entries after the snapshot are trimmed"
        assert analysis["biorxiv/genomics"]["total"] == 150
        assert analysis["biorxiv/genomics"]["all_dates"][-1] > analysis["biorxiv/genomics"]["first_page_dates"][-1]
        print(f"{moment:%Y-%m-%d_%H%M}: " + "; ".join(notes[len(window_notes):]))
    print("selftest collector checks passed")


if __name__ == "__main__":
    main()
