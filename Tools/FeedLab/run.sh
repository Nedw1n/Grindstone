#!/bin/bash
# Usage: run.sh [--rev <git-rev | WORKTREE>] [--data <dir>] [--report <file.md>]
#
# Builds the app's feed code at --rev (default WORKTREE) with the replay
# harness and replays every snapshot in --data (default Tools/FeedLab/data).
# Uses swiftc when installed, otherwise the official Swift image in Docker.
set -euo pipefail
lab=$(cd "$(dirname "$0")" && pwd)
rev=WORKTREE
data="$lab/data"
report="$lab/reports/replay.md"
while [ $# -gt 0 ]; do
  case $1 in
    --rev) rev=$2; shift 2 ;;
    --data) data=$(cd "$2" && pwd); shift 2 ;;
    --report) report=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$report")"
report=$(cd "$(dirname "$report")" && pwd)/$(basename "$report")

build="$lab/build/$(echo "$rev" | tr '/' '_')"
"$lab/prep.sh" "$rev" "$build/src"
cp "$lab/eval/main.swift" "$build/src/main.swift"

flags=(-swift-version 5 -default-isolation MainActor
  -enable-upcoming-feature InferIsolatedConformances
  -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferSendableFromCaptures
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability
  -enable-upcoming-feature DisableOutwardActorInference
  -enable-upcoming-feature MemberImportVisibility
  -suppress-warnings)

if command -v swiftc > /dev/null; then
  swiftc "${flags[@]}" -module-name Grindstone "$build"/src/*.swift -o "$build/replay"
  HOME="$build/home" "$build/replay" "$data" "$report"
else
  image=${SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.2-noble}
  docker run --rm -v "$lab:$lab" -v "$data:$data" -v "$(dirname "$report"):$(dirname "$report")" \
    -w "$lab" "$image" bash -c "
      swiftc ${flags[*]} -module-name Grindstone '$build'/src/*.swift -o '$build/replay' &&
      HOME='$build/home' '$build/replay' '$data' '$report'"
fi
