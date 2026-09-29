#!/usr/bin/env python3
"""Tries ranking alternatives on the app's own replayed output.

Reads the per-snapshot exports that run.sh writes (<report>.lanes/*.json):
the stories the app put on the front page, with the fields its ranking uses.
Each variant re-orders that same set, so differences come from the ranking
alone. Nothing here changes the app.

  analyze.py reports/current.md.lanes [--data data] > reports/variants.md
"""

import argparse
import collections
import datetime as dt
import glob
import html
import json
import math
import os
import re
import statistics
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")
EDITORIAL = {"HN", "Memo"}
SOURCES = ["HN", "Memo", "Bio", "RSS"]

# The app's current weights (FeedRankingEngine).
W_PLACE, W_CROSS, W_RECENCY, HALF_LIFE = 0.5, 0.35, 0.15, 6.0


def recency(age_hours, half_life=HALF_LIFE):
    return 0.5 ** (max(age_hours, 0) / half_life)


def placement(item):
    return item["intraSourceRank"] if item["source"] in EDITORIAL else 0.5


def current_score(item, now, **overrides):
    age = (now - item["publishedAt"]) / 3600
    return (W_PLACE * overrides.get("place", placement(item))
            + W_CROSS * len(item["crossRefs"]) / 3
            + W_RECENCY * recency(age))


# MARK: - Memeorandum dates estimated from permalink order

def memo_estimated_times(snapshot_dir, lane):
    """Permalink IDs (260929p60) number stories in posting order through each
    Eastern day. Items with a feed date anchor the day; others are placed by
    linear interpolation from midnight Eastern to the latest anchor."""
    path = os.path.join(snapshot_dir, "www.memeorandum.com_")
    if not os.path.exists(path):
        return {}
    page = open(path, encoding="utf-8").read()
    top = page[page.find('<SPAN CLASS="rnhd2">Top Items:</SPAN>'):]
    url_to_id = {}
    for cluster in top.split('<DIV CLASS="clus">')[1:]:
        item_id = re.search(r'<DIV CLASS="item" ID="(\d{6})p(\d+)"', cluster)
        link = re.search(r'<DIV CLASS="ii"><STRONG CLASS="L\d"><A HREF="([^"]+)"', cluster)
        if item_id and link:
            url_to_id[html.unescape(link.group(1))] = (item_id.group(1), int(item_id.group(2)))
    anchors = collections.defaultdict(list)
    for item in lane:
        key = url_to_id.get(item["url"])
        if key and item["hasDiscussion"]:
            anchors[key[0]].append((key[1], item["publishedAt"]))
    max_seen = collections.defaultdict(int)
    for day, n in url_to_id.values():
        max_seen[day] = max(max_seen[day], n)
    estimates = {}
    for item in lane:
        key = url_to_id.get(item["url"])
        if not key or item["hasDiscussion"]:
            continue
        day, n = key
        start = dt.datetime.strptime(day, "%y%m%d").replace(tzinfo=EASTERN).timestamp()
        if anchors[day]:
            n_anchor, t_anchor = max(anchors[day])
            estimates[item["id"]] = start + (n / n_anchor) * (t_anchor - start)
        else:  # an earlier day with no anchor: spread its numbers over the day
            estimates[item["id"]] = start + (n / max(max_seen[day], 1)) * 86400
    return estimates


# MARK: - Variants

def order_by(items, key):
    return sorted(items, key=key, reverse=True)


def v_current(items, now, ctx):
    return order_by(items, lambda i: current_score(i, now))


def v_page_placement(items, now, ctx):
    """Placement by position on a 30-story page, not by fetch size (HN 60 vs Memo 40)."""
    def place(i):
        if i["source"] not in EDITORIAL:
            return 0.5
        count = ctx["laneCount"].get(i["source"], 30)
        index = round((1 - i["intraSourceRank"]) * count)
        return max(0.0, 1 - index / 30)
    return order_by(items, lambda i: current_score(i, now, place=place(i)))


def v_memo_dates(items, now, ctx):
    """Memeorandum stories without a feed entry get an estimated time instead of midnight UTC."""
    est = ctx["memoEstimates"]
    def score(i):
        if i["id"] in est:
            shifted = dict(i, publishedAt=est[i["id"]])
            return current_score(shifted, now)
        return current_score(i, now)
    return order_by(items, score)


def v_editorial_no_recency(items, now, ctx):
    """HN and Memeorandum already decay with age on their own pages; don't count time twice."""
    def score(i):
        if i["source"] in EDITORIAL:
            return W_PLACE * placement(i) + W_CROSS * len(i["crossRefs"]) / 3 + W_RECENCY * 0.5
        return current_score(i, now)
    return order_by(items, score)


def v_reserved_slots(items, now, ctx):
    """Current order, but the best story under a day old from each non-editorial
    source is lifted to #5 and #10 when it isn't already above them."""
    ranked = v_current(items, now, ctx)
    picks = []
    for source in ("Bio", "RSS"):
        fresh = [i for i in ranked if i["source"] == source and now - i["publishedAt"] < 86400]
        if fresh:
            picks.append(fresh[0])
    picks.sort(key=lambda i: -current_score(i, now))
    result = [i for i in ranked if i not in picks]
    for slot, pick in zip((4, 9), picks):
        if ranked.index(pick) > slot:
            result.insert(slot, pick)
        else:
            result.insert(ranked.index(pick), pick)
    return result


def v_diversity_cap(items, now, ctx):
    """Greedy: after the first five, no source holds more than 60% of the list so far."""
    remaining = v_current(items, now, ctx)
    result, counts = [], collections.Counter()
    while remaining:
        position = len(result) + 1
        cap = max(3, math.ceil(0.6 * position))
        pick = next((i for i in remaining if counts[i["source"]] + 1 <= cap), remaining[0])
        remaining.remove(pick)
        result.append(pick)
        counts[pick["source"]] += 1
    return result


def v_combined(items, now, ctx):
    """Page placement + estimated Memeorandum dates + no double recency for editorial
    sources, then the diversity cap."""
    est = ctx["memoEstimates"]
    def score(i):
        if i["source"] in EDITORIAL:
            count = ctx["laneCount"].get(i["source"], 30)
            index = round((1 - i["intraSourceRank"]) * count)
            return W_PLACE * max(0.0, 1 - index / 30) + W_CROSS * len(i["crossRefs"]) / 3 + W_RECENCY * 0.5
        return current_score(dict(i, publishedAt=est.get(i["id"], i["publishedAt"])), now)
    remaining = order_by(items, score)
    result, counts = [], collections.Counter()
    while remaining:
        cap = max(3, math.ceil(0.6 * (len(result) + 1)))
        pick = next((i for i in remaining if counts[i["source"]] + 1 <= cap), remaining[0])
        remaining.remove(pick)
        result.append(pick)
        counts[pick["source"]] += 1
    return result


VARIANTS = [
    ("current", v_current),
    ("page placement", v_page_placement),
    ("Memo dates estimated", v_memo_dates),
    ("no double recency", v_editorial_no_recency),
    ("reserved slots", v_reserved_slots),
    ("diversity cap", v_diversity_cap),
    ("combined", v_combined),
]


# MARK: - Metrics

def kendall(order, source):
    led = [i for i in order if i["source"] == source]
    c = d = 0
    for a in range(len(led)):
        for b in range(a + 1, len(led)):
            x, y = led[a]["intraSourceRank"], led[b]["intraSourceRank"]
            if x == y:
                continue
            if x > y:
                c += 1
            else:
                d += 1
    return (c - d) / (c + d) if c + d else None


def metrics(order, now, baseline):
    top10, top20 = order[:10], order[:20]
    first = {s: next((n + 1 for n, i in enumerate(order) if i["source"] == s), None) for s in SOURCES}
    ages = sorted((now - i["publishedAt"]) / 3600 for i in top10)
    base_ids = {i["id"] for i in baseline[:10]}
    return {
        "top10": collections.Counter(i["source"] for i in top10),
        "top20": collections.Counter(i["source"] for i in top20),
        "first": first,
        "tauHN": kendall(order, "HN"),
        "tauMemo": kendall(order, "Memo"),
        "medianAge": ages[len(ages) // 2] if ages else None,
        "kept": len(base_ids & {i["id"] for i in top10}),
        "scoreTop10": sum(current_score(i, now) for i in top10) / max(len(top10), 1),
    }


def fmt_counts(counter):
    return "/".join(str(counter.get(s, 0)) for s in SOURCES)


def mean(values):
    values = [v for v in values if v is not None]
    return statistics.mean(values) if values else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("lanes")
    parser.add_argument("--data", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
    args = parser.parse_args()

    runs = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(args.lanes, "*.json")))]
    out = ["# Ranking variants on replayed snapshots", ""]
    summary = collections.defaultdict(list)

    for run in runs:
        now = run["time"]
        items = run["front"]
        lane_counts = {s: len(v) for s, v in run["lanes"].items()}
        estimates = memo_estimated_times(os.path.join(args.data, run["id"]), run["lanes"].get("Memo", []))
        ctx = {"laneCount": lane_counts, "memoEstimates": estimates}
        baseline = v_current(items, now, ctx)
        # Sanity check: the re-implementation must reproduce the app's order.
        assert [i["id"] for i in baseline] == [i["id"] for i in items] or all(
            abs(current_score(a, now) - current_score(b, now)) < 1e-9 for a, b in zip(baseline, items)
        ), f"{run['id']}: re-scored order differs from the app"
        out += [f"## {run['id']}", "",
                "| Variant | Top 10 HN/Memo/Bio/RSS | Top 20 | First Bio | First RSS | τ HN | τ Memo | Median age top 10 (h) | Kept of current top 10 | Mean current score of top 10 |",
                "|---|---|---|---|---|---|---|---|---|---|"]
        for name, variant in VARIANTS:
            order = variant(list(items), now, ctx)
            m = metrics(order, now, baseline)
            summary[name].append((run["id"], m))
            tau_memo = "–" if m["tauMemo"] is None else "%.2f" % m["tauMemo"]
            out.append(
                f"| {name} | {fmt_counts(m['top10'])} | {fmt_counts(m['top20'])} | {m['first']['Bio'] or '–'} | {m['first']['RSS'] or '–'} "
                f"| {m['tauHN']:.2f} | {tau_memo} | {m['medianAge']:.1f} | {m['kept']} | {m['scoreTop10']:.3f} |"
            )
        if run["id"].startswith("live"):
            order = v_combined(list(items), now, ctx)
            out += ["", "Top 12 under `combined`:", ""]
            out += [f"{n + 1}. [{i['source']}] {i['title'][:90]}" for n, i in enumerate(order[:12])]
            if estimates:
                out += ["", f"Memeorandum stand-in dates replaced by estimates for {len(estimates)} stories."]
        out.append("")

    out += ["## Averages across snapshots", "",
            "| Variant | Snapshots | Top 10 HN/Memo/Bio/RSS | First Bio | First RSS | τ HN | Median age top 10 (h) | Kept of current top 10 | Mean current score of top 10 |",
            "|---|---|---|---|---|---|---|---|---|"]
    for name, _ in VARIANTS:
        rows = [m for _, m in summary[name]]
        top10 = collections.Counter()
        for m in rows:
            top10.update(m["top10"])
        avg = "/".join(f"{top10.get(s, 0) / len(rows):.1f}" for s in SOURCES)
        out.append(f"| {name} | {len(rows)} | {avg} | {mean(m['first']['Bio'] for m in rows):.1f} | {mean(m['first']['RSS'] for m in rows):.1f} "
                   f"| {mean(m['tauHN'] for m in rows):.2f} | {mean(m['medianAge'] for m in rows):.1f} | {mean(m['kept'] for m in rows):.1f} | {mean(m['scoreTop10'] for m in rows):.3f} |")
    print("\n".join(out))


if __name__ == "__main__":
    main()
