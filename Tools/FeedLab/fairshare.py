#!/usr/bin/env python3
"""A source-agnostic way to build Today, tested against the current ranking.

Nothing in the strategy knows about Hacker News, Memeorandum, biotech or RSS.
It only knows, for each channel (one feed or one ranked page):
  kind     "ranked" (the channel publishes an order) or "chronological"
  group    what the reader thinks of as a source or topic
and, per group, a weight: the share of Today it should get.

  standing   ranked:        1 - position / 30, by position on the page,
                            whatever the fetch size
             chronological: freshness on the channel's own clock, halving
                            every 2 x its typical gap between posts
                            (clamped to 3..24 h), so a weekly blog and a
                            wire feed are judged by their own rhythm
  eligible   ranked items always; chronological items while standing >= 0.35
             (about 1.5 of their own half-lives); nothing over 36 h
  cross-post a story carried by n groups gains 0.25 x (n - 1) standing and
             counts toward whichever group takes it first
  merge      weighted deficit round robin: each position goes to the group
             furthest below its share of the list so far, which takes its
             best remaining story (channels inside a group take turns the
             same way). A group with nothing eligible gives up its turn.

Scenarios, all from replayed real data:
  as is          the snapshot's own sources
  STAT as feed   STAT also added as a personal RSS feed beside Marginal
                 Revolution (and taken out of Biotech), to see whether a busy
                 feed crowds out a quiet one
  HN-heavy       group weights HN 2, Memo 2, Bio 1, RSS 1 (the weights are the
                 reader's knob)

  fairshare.py reports/current.md.lanes [--data data] > reports/fairshare.md
"""

import argparse
import collections
import email.utils
import glob
import html
import json
import os
import re
import statistics

import analyze  # current scoring and helpers

PAGE = 30
MAX_AGE_H = 36
FLOOR = 0.35


# MARK: - Channels and standing

def channel_of(item):
    return item["source"] if item["source"] in analyze.EDITORIAL else f"{item['source']}:{item['outlet']}"


def kind_of(item):
    return "ranked" if item["source"] in analyze.EDITORIAL else "chronological"


def half_lives(candidates):
    """Per chronological channel: 2 x median gap between its posts, clamped."""
    times = collections.defaultdict(list)
    for item in candidates:
        if kind_of(item) == "chronological":
            times[item["channel"]].append(item["publishedAt"])
    result = {}
    for channel, stamps in times.items():
        stamps.sort(reverse=True)
        gaps = [(a - b) / 3600 for a, b in zip(stamps, stamps[1:]) if a > b]
        typical = statistics.median(gaps) if gaps else 24
        result[channel] = min(max(2 * typical, 3), 24)
    return result


def standing(item, now, lives):
    age = (now - item["publishedAt"]) / 3600
    if kind_of(item) == "ranked":
        base = max(0.0, 1 - item["position"] / PAGE)
    else:
        base = 0.5 ** (max(age, 0) / lives.get(item["channel"], 12))
    return min(1.0, base + 0.25 * (len(item["groups"]) - 1))


def eligible(item, now, lives):
    age = (now - item["publishedAt"]) / 3600
    if age > MAX_AGE_H:
        return False
    return kind_of(item) == "ranked" or standing(item, now, lives) >= FLOOR


def fair_share(candidates, now, weights):
    lives = half_lives(candidates)
    pool = [dict(i, standing=standing(i, now, lives)) for i in candidates if eligible(i, now, lives)]
    total = sum(weights.get(g, 1) for g in {g for i in pool for g in i["groups"]}) or 1
    taken_group = collections.Counter()
    taken_channel = collections.Counter()
    result = []
    while pool:
        k = len(result) + 1
        groups = {g for i in pool for g in i["groups"]}
        # The group furthest below its share of the first k positions.
        group = max(groups, key=lambda g: (weights.get(g, 1) / total * k - taken_group[g],
                                           max(i["standing"] for i in pool if g in i["groups"])))
        in_group = [i for i in pool if group in i["groups"]]
        channels = {i["channel"] for i in in_group}
        channel = max(channels, key=lambda c: (-taken_channel[(group, c)],
                                               max(i["standing"] for i in in_group if i["channel"] == c)))
        pick = max((i for i in in_group if i["channel"] == channel), key=lambda i: i["standing"])
        pool.remove(pick)
        result.append(pick)
        for g in pick["groups"]:
            taken_group[g] += 1
        taken_channel[(group, channel)] += 1
    return result


# MARK: - Candidates from a replayed snapshot

def candidates_from(run):
    """Every story the app fetched, one entry per merged story, with its channel,
    kind, the groups carrying it, and its position on its own page."""
    lead_of = run["leadIDs"]
    members = collections.defaultdict(list)
    for source, lane in run["lanes"].items():
        for item in lane:
            members[lead_of.get(item["id"], item["id"])].append(item)
    stories = []
    for lead_id, group in members.items():
        lead = next((i for i in group if i["id"] == lead_id), group[0])
        item = dict(lead)
        item["groups"] = sorted({m["source"] for m in group})
        item["channel"] = channel_of(lead)
        item["position"] = lead.get("laneIndex", 0)
        stories.append(item)
    return stories


def stat_as_personal_feed(run, data_dir):
    """Scenario: the reader adds STAT as their own RSS feed (and Biotech no longer
    carries it). Returns (candidates for fair share, the app's own RSS lane)."""
    path = os.path.join(data_dir, run["id"], "www.statnews.com_feed_")
    if not os.path.exists(path):
        return None
    xml = open(path, encoding="utf-8").read()
    stat = []
    for block in re.findall(r"<item>.*?</item>", xml, re.S):
        title = html.unescape(re.sub(r"<!\[CDATA\[|\]\]>", "", re.search(r"<title>(.*?)</title>", block, re.S).group(1))).strip()
        link = re.search(r"<link>(.*?)</link>", block, re.S).group(1).strip()
        date = email.utils.parsedate_to_datetime(re.search(r"<pubDate>(.*?)</pubDate>", block).group(1)).timestamp()
        if date <= run["time"]:
            stat.append({"id": link, "title": title, "url": link, "source": "RSS", "outlet": "STAT",
                         "publishedAt": date, "crossRefs": [], "intraSourceRank": 0.5})
    lanes = {s: [dict(i) for i in lane if not (s == "Bio" and i["outlet"] == "STAT")] for s, lane in run["lanes"].items()}
    # The app's RSS lane: every personal feed merged newest first, capped at 32.
    rss = sorted(lanes.get("RSS", []) + stat, key=lambda i: -i["publishedAt"])[:32]
    for index, item in enumerate(rss):
        item["laneIndex"] = index
    lanes["RSS"] = rss
    return dict(run, lanes=lanes)


def current_front(run):
    """The app's front page for a (possibly modified) set of lanes: each source's
    top slice, ordered by the current score."""
    limits = {"HN": 20, "Memo": 20, "Bio": 15, "RSS": 20}
    front = []
    for source, lane in run["lanes"].items():
        front += [dict(i, groups=[source], channel=channel_of(i)) for i in lane[: limits.get(source, 20)]]
    return analyze.order_by(front, lambda i: analyze.current_score(i, run["time"]))


# MARK: - Metrics

def describe(order, now, label):
    top10, top20 = order[:10], order[:20]
    ages = sorted((now - i["publishedAt"]) / 3600 for i in top10)
    by_group = lambda items: collections.Counter(i["source"] for i in items)
    first = {s: next((n + 1 for n, i in enumerate(order) if i["source"] == s), None) for s in analyze.SOURCES}
    rss_channels = collections.Counter(i["outlet"] for i in top20 if i["source"] == "RSS")
    ranked_in_order = all(
        a["intraSourceRank"] >= b["intraSourceRank"]
        for s in analyze.EDITORIAL
        for a, b in zip([i for i in order if i["source"] == s], [i for i in order if i["source"] == s][1:])
    )
    return {
        "label": label,
        "top10": by_group(top10), "top20": by_group(top20), "first": first,
        "medianAge": ages[len(ages) // 2] if ages else None, "maxAge": ages[-1] if ages else None,
        "rssChannels": rss_channels, "editorialOrderKept": ranked_in_order,
    }


def row(d):
    fmt = lambda c: "/".join(str(c.get(s, 0)) for s in analyze.SOURCES)
    first = " ".join(f"{s}#{d['first'][s]}" for s in analyze.SOURCES if d["first"][s])
    rss = ", ".join(f"{k} {v}" for k, v in sorted(d["rssChannels"].items())) or "–"
    return (f"| {d['label']} | {fmt(d['top10'])} | {fmt(d['top20'])} | {first} | {d['medianAge']:.1f} / {d['maxAge']:.1f} "
            f"| {rss} | {'yes' if d['editorialOrderKept'] else 'no'} |")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("lanes")
    parser.add_argument("--data", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
    args = parser.parse_args()
    runs = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(args.lanes, "*.json")))]
    equal = collections.defaultdict(lambda: 1)
    tilted = {"HN": 2, "Memo": 2, "Bio": 1, "RSS": 1}
    header = ("| Strategy | Top 10 HN/Memo/Bio/RSS | Top 20 | First of each | Top 10 age median / max (h) "
              "| Personal feeds in top 20 | HN/Memo order kept |\n|---|---|---|---|---|---|---|")
    out = ["# Fair share vs current ranking", ""]
    totals = collections.defaultdict(list)
    for run in runs:
        now = run["time"]
        out += [f"## {run['id']}", "", header]
        scenarios = [("as is", run)]
        stat_run = stat_as_personal_feed(run, args.data)
        if stat_run:
            scenarios.append(("STAT as feed", stat_run))
        for name, scenario in scenarios:
            # As is: the app's actual front page. Otherwise: its slices re-scored.
            front = run["front"] if name == "as is" else current_front(scenario)
            cur = describe(front, now, f"current · {name}")
            fair = describe(fair_share(candidates_from(scenario), now, equal), now, f"fair share · {name}")
            out += [row(cur), row(fair)]
            totals[f"current · {name}"].append(cur)
            totals[f"fair share · {name}"].append(fair)
            if name == "as is":
                heavy = describe(fair_share(candidates_from(scenario), now, tilted), now, "fair share · HN-heavy")
                out.append(row(heavy))
                totals["fair share · HN-heavy"].append(heavy)
        if run["id"].startswith("live"):
            out += ["", "Top 12 under fair share (live, equal weights):", ""]
            for n, i in enumerate(fair_share(candidates_from(run), now, equal)[:12]):
                out.append(f"{n + 1}. [{'+'.join(i['groups'])}] {i['title'][:88]} ({(now - i['publishedAt']) / 3600:.1f} h)")
        out.append("")

    out += ["## Averages", "",
            "| Strategy | Snapshots | Top 10 HN/Memo/Bio/RSS | Top 10 age median / max (h) | Marginal Revolution / STAT in top 20 | HN/Memo order kept |",
            "|---|---|---|---|---|---|"]
    for label, rows in totals.items():
        top10 = collections.Counter()
        rss = collections.Counter()
        for d in rows:
            top10.update(d["top10"])
            rss.update(d["rssChannels"])
        n = len(rows)
        out.append(f"| {label} | {n} | " + "/".join(f"{top10.get(s, 0) / n:.1f}" for s in analyze.SOURCES)
                   + f" | {statistics.mean(d['medianAge'] for d in rows):.1f} / {statistics.mean(d['maxAge'] for d in rows):.1f}"
                   + f" | {rss.get('Marginal Revolution', 0) / n:.1f} / {rss.get('STAT', 0) / n:.1f}"
                   + f" | {sum(d['editorialOrderKept'] for d in rows)}/{n} |")
    print("\n".join(out))


if __name__ == "__main__":
    main()
