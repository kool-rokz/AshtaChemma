#!/usr/bin/env bash
# Brings new or changed audio files in assets/audio/ into the game: imports them, sets
# music and ambience to loop (import settings), imports those again, then makes or
# updates the sound resources (tools/SyncAudio.gd: cues, music tracks, figure voices).
# Run by AshtaChemmaArt/audio/build.sh --install; safe to run any time.
# With the editor open, rescan it afterwards (or let it notice the changes).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"

cd "$HERE"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tools/SyncAudio.gd -- --loops 2>&1 | grep "SyncAudio" || true
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tools/SyncAudio.gd 2>&1 | grep -E "SyncAudio|ERROR" || true
