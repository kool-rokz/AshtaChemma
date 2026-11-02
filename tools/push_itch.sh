#!/usr/bin/env bash
# Builds the game and uploads it to itch.io with butler.
#   bash tools/push_itch.sh yourname/ashta-chemma
#   ITCH_TARGET=yourname/ashta-chemma bash tools/push_itch.sh
#   SKIP_TESTS=1 ...      skip the test suites (not recommended)
#   DRY_RUN=1 ...         build and check everything, but don't upload
# Steps: check butler can reach the page (you're logged in and own it), run the test
# suites, export into build/v<GAME_VERSION>/ (tools/export_builds.sh), then push the web
# build to the "html5" channel and the Windows build to the "windows" channel, tagged
# with the game version the menu shows. butler only uploads changed bytes.
#
# Page settings are NOT set by butler; set them once in the itch.io dashboard (Edit game):
#   - Visibility & access: "Restricted", with a password (only people you give it to can play)
#   - the html5 upload: tick "This file will be played in the browser" (once, after the
#     first push; later pushes keep it)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
TARGET="${1:-${ITCH_TARGET:-}}"
if [ -z "$TARGET" ] || [[ "$TARGET" != */* ]]; then
	echo "Usage: bash tools/push_itch.sh <itch-user>/<game>   (or set ITCH_TARGET)" >&2
	exit 2
fi

BUTLER="$(command -v butler || true)"
[ -z "$BUTLER" ] && [ -x "/c/Program Files (x86)/butler/butler.exe" ] && BUTLER="/c/Program Files (x86)/butler/butler.exe"
if [ -z "$BUTLER" ]; then
	echo "butler not found: put it on PATH (or set BUTLER=...)" >&2
	exit 2
fi

VERSION="$(sed -n 's/^const GAME_VERSION := "\(.*\)"/\1/p' game_config/GameConfig.gd)"
[ -n "$VERSION" ] || { echo "Couldn't read GAME_VERSION from game_config/GameConfig.gd" >&2; exit 2; }
echo "== AshtaChemma v$VERSION -> $TARGET"

echo "== Checking butler can reach $TARGET"
if ! "$BUTLER" status "$TARGET" >/dev/null 2>&1; then
	echo "butler can't see $TARGET. Run 'butler login', and check the user/game name (the game must exist on itch.io already)." >&2
	exit 1
fi

if [ -z "${SKIP_TESTS:-}" ]; then
	echo "== Running the test suites"
	run() {
		local log
		if ! log="$("$GODOT" --headless --path . "$@" 2>&1)" || ! grep -q "PASS" <<<"$log"; then
			echo "$log" | tail -20
			echo "TESTS FAILED: $* (nothing uploaded)" >&2
			exit 1
		fi
		echo "   ok: $*"
	}
	run -s res://tests/BoardPathTest.gd
	run -s res://tests/BoardMapTest.gd
	run -s res://tests/NearMissTest.gd
	run -s res://tests/OpenDraftTest.gd
	run --time-scale 20 res://tests/RulesTest.tscn
	run --time-scale 20 res://tests/CardsTest.tscn
	run --time-scale 30 res://tests/ReplayTest.tscn
	run --time-scale 30 res://tests/NetTest.tscn
	run -s res://tests/CowryDistributionTest.gd
	run -s res://tests/ShellSimTest.gd
	run --time-scale 50 res://tests/SimulationTest.tscn -- --players=4 --cards
	run --time-scale 50 res://tests/SimulationTest.tscn -- --players=4 --cards --open-draft
fi

echo "== Exporting"
BUILD_DIR="build/v$VERSION" bash tools/export_builds.sh
OUT="build/v$VERSION"
# Editor leftovers that don't belong in an upload
find "$OUT/web" -name "*.import" -delete

if [ -n "${DRY_RUN:-}" ]; then
	echo "== Dry run: would push $OUT/web -> $TARGET:html5 and $OUT/windows -> $TARGET:windows (v$VERSION)"
	exit 0
fi

echo "== Uploading"
"$BUTLER" push "$OUT/web" "$TARGET:html5" --userversion "$VERSION"
"$BUTLER" push "$OUT/windows" "$TARGET:windows" --userversion "$VERSION"

echo "== Done. Channels on itch.io:"
"$BUTLER" status "$TARGET"
cat <<'EOF'

Check once on the itch.io dashboard (butler can't change these):
  - Visibility & access: Restricted, with a password
  - the html5 upload: "This file will be played in the browser" ticked
Players get the new build on their next page load (Ctrl+Shift+R if the menu shows the old version).
EOF
