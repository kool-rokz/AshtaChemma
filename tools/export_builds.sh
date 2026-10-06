#!/usr/bin/env bash
# Builds the itch.io web zip and the Windows zip into build/.
#   bash tools/export_builds.sh                 (into build/)
#   BUILD_DIR=build/v0.4.0 bash tools/export_builds.sh   (elsewhere, e.g. while the old exe runs)
# Exports from a clean copy of the project (no editor-only add-ons such as the MCP
# tools), so the shipped game never contains them. Needs Godot 4.7.2 export templates
# (Editor > Manage Export Templates).
set -euo pipefail

GODOT="${GODOT:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$ROOT" && mkdir -p "${BUILD_DIR:-build}" && cd "${BUILD_DIR:-build}" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "== Copying the project (tracked + new files, skipping ignored ones)"
cd "$ROOT"
# (files deleted in the working tree but still tracked are skipped; any other copy error stops the build)
git ls-files -co --exclude-standard -z | while IFS= read -r -d '' f; do
	if [ -e "$f" ]; then cp --parents "$f" "$STAGE/"; fi
done
# Editor-only entries the MCP plugin adds to project.godot while the editor is open
sed -i '/^\[autoload\]/,/^\[/{/MCP[A-Za-z]*=/d}' "$STAGE/project.godot"
sed -i '/godot_mcp\/plugin.cfg/d' "$STAGE/project.godot"

echo "== Importing assets"
"$GODOT" --headless --path "$STAGE" --import >/dev/null 2>&1 || true

rm -rf "$OUT/web" "$OUT/windows"
mkdir -p "$OUT/web" "$OUT/windows"

echo "== Exporting Web"
"$GODOT" --headless --path "$STAGE" --export-release "Web" "$OUT/web/index.html" 2>&1 | grep -E "ERROR|error" || true
echo "== Exporting Windows"
"$GODOT" --headless --path "$STAGE" --export-release "Windows Desktop" "$OUT/windows/AshtaChemma.exe" 2>&1 | grep -E "ERROR|error" || true

[ -f "$OUT/web/index.html" ] || { echo "Web export failed"; exit 1; }
[ -f "$OUT/windows/AshtaChemma.exe" ] || { echo "Windows export failed"; exit 1; }

echo "== Zipping"
rm -f "$OUT/AshtaChemma-web.zip" "$OUT/AshtaChemma-windows.zip"
# itch.io wants index.html at the root of the zip
powershell.exe -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$OUT/web")\\*' -DestinationPath '$(cygpath -w "$OUT/AshtaChemma-web.zip")'"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$OUT/windows")\\*' -DestinationPath '$(cygpath -w "$OUT/AshtaChemma-windows.zip")'"
ls -la "$OUT"/*.zip
echo "Done."
