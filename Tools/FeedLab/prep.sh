#!/bin/bash
# Usage: prep.sh <git-rev | WORKTREE> <out-dir>
#
# Assembles Grindstone's non-UI code at <git-rev> (or the working tree) into
# <out-dir>, ready to build on Linux with the replay harness:
#  - Foundation's networking and XML modules imported (separate on Linux)
#  - Combine and SwiftUI replaced by the small shims in shims/
#  - networking replaced by replay/ReplayNetworking.swift
#  - the ranking engine's clock pointed at the moment being replayed
#  - the SwiftUI-only OPML export removed
set -euo pipefail
rev=$1
out=$2
lab=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$lab/../.." && pwd)

files=(
  Models/FeedItem.swift Models/Source.swift
  Services/CrossRefEngine.swift Services/FeedRankingEngine.swift
  Services/RSSService.swift Services/BiotechService.swift
  Services/MemeorandumService.swift Services/HNService.swift
  Services/FeedFetchError.swift Services/FeedCacheStore.swift
  Services/FeedSourceCatalog.swift Services/ManualRSSFeedStore.swift
  Services/RSSOPMLSupport.swift Services/FeedPreferences.swift
  Services/FeedUserStateStore.swift
  Utilities/StringSanitization.swift
  ViewModels/FeedViewModel.swift
)

source_of() {
  if [ "$rev" = WORKTREE ]; then
    cat "$repo/Grindstone/$1"
  else
    git -C "$repo" show "$rev:Grindstone/$1"
  fi
}

rm -rf "$out"
mkdir -p "$out"
for f in "${files[@]}"; do
  {
    printf '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n'
    printf '#if canImport(FoundationXML)\nimport FoundationXML\n#endif\n'
    source_of "$f" | sed -e '/^import Combine$/d' -e '/^import SwiftUI$/d' \
      -e '/^import UniformTypeIdentifiers$/d' -e '/^import CoreTransferable$/d'
  } > "$out/$(basename "$f")"
done

awk '/^(struct RSSOPMLExport: Transferable|extension UTType)/ {skip=1} !skip {print} skip && /^}$/ {skip=0}' \
  "$out/RSSOPMLSupport.swift" > "$out/tmp" && mv "$out/tmp" "$out/RSSOPMLSupport.swift"

# Score recency against the replayed moment rather than the real clock.
sed -i -e 's/let now = Date()/let now = ReplayClock.now/g' \
       -e 's/now: Date = Date()/now: Date = ReplayClock.now/g' \
       "$out/FeedRankingEngine.swift"
if grep -q 'Date()' "$out/FeedRankingEngine.swift"; then
  echo "prep.sh: FeedRankingEngine still reads Date(); point it at ReplayClock" >&2
  exit 1
fi

cp "$lab"/shims/*.swift "$lab"/replay/*.swift "$out/"
