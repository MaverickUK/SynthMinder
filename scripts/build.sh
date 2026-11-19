#!/usr/bin/env bash
# Build SynthMinder and its tests with Turbo Pascal 7 in DOSBox-X, without a
# window, then run the tests and the demo:
#
#   build/tp7/SYNMIND.EXE, TESTS.EXE    the programs
#   build/tp7/BUILD.LOG                 the compiler's output
#   build/tp7/TESTS.TXT                 the unit tests' results
#   build/tp7/STATUS.TXT                SYNMIND /DEMO /STATUS
#   build/tp7/SOUND.BIN, FLOPPY.BIN,    the demo's tabs (scripts/screen.py shows them)
#     HARDDISK.BIN, CDROM.BIN,
#     SETTINGS.BIN
#   build/tp7/KEYS.BIN                  the screen after a scripted session at the keyboard,
#     KEYS1.BIN to KEYS5.BIN            and each tab then
#
# Usage: scripts/build.sh [--run]     --run: then open the demo in a DOSBox-X window
#
# Needs DOSBox-X (on PATH, or DOSBOX_X), Python 3 and Turbo Pascal 7 (TP_DIR,
# default C:\TPWDB, holding BIN\TPC.EXE).
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/build/tp7"
run=
[ "${1:-}" = "--run" ] && run=1

native() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

dosbox=${DOSBOX_X:-$(command -v dosbox-x || true)}
for guess in "$HOME/scoop/apps/dosbox-x/current/dosbox-x.exe" "/c/Program Files/DOSBox-X/dosbox-x.exe"; do
  if [ -z "$dosbox" ] && [ -x "$guess" ]; then dosbox=$guess; fi
done
[ -n "$dosbox" ] || { echo "DOSBox-X not found: install it or set DOSBOX_X" >&2; exit 1; }

python=
for p in python3 python py; do
  if "$p" -c 'import sys; sys.exit(sys.version_info < (3, 6))' 2> /dev/null; then python=$p; break; fi
done
[ -n "$python" ] || { echo "Python 3 not found" >&2; exit 1; }

tp_dir=${TP_DIR:-/c/TPWDB}
[ -f "$tp_dir/BIN/TPC.EXE" ] || { echo "Turbo Pascal not found at $tp_dir/BIN/TPC.EXE: set TP_DIR" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out"

# A session at the keyboard, saved as KEYS.BIN when it exits (and each tab as KEYS1.BIN
# to KEYS5.BIN). On the Sound tab: the pack above the one playing (Voice coil 1991),
# volume up twice (to 70) and balance right once (to 60). Past Floppy to the Hard disk
# tab: up from the disk DOS runs from to DOSBENCH.IMG, for the next reset. On the
# CD-ROM tab: down from the disc in the drive to QUAKE.ISO, into the drive. Each confirmed
keys="up enter equals equals period right right up up up enter enter right down enter enter esc"

# Compile everything (/B) so stale units are never used. S: is the repository, read only
tpc='T:\BIN\TPC.EXE /B /Q /EC:\ /US:\;T:\UNITS /IS:\'
conf="$out/dosbox.conf"
{
  printf '[sdl]\r\nautolock=false\r\n'
  printf '[dosbox]\r\ntitle=SynthMinder build\r\nmemsize=16\r\n'
  printf '[cpu]\r\ncycles=max\r\n'
  printf '[autoexec]\r\n'
  printf '%s\r\n' \
    "mount c \"$(native "$out")\"" \
    "mount -ro s \"$(native "$repo")\"" \
    "mount -ro t \"$(native "$tp_dir")\"" \
    'c:' \
    "$tpc S:\\SYNMIND.PAS > BUILD.LOG" \
    "$tpc S:\\TESTS\\TESTS.PAS >> BUILD.LOG" \
    'TESTS.EXE > TESTS.TXT' \
    'SYNMIND.EXE /V > VERSION.TXT' \
    'SYNMIND.EXE /DEMO /STATUS > STATUS.TXT' \
    'SYNMIND.EXE /DEMO /DUMP=SOUND' \
    'copy SCREEN.BIN SOUND.BIN > NUL' \
    'SYNMIND.EXE /DEMO /DUMP=FLOPPY' \
    'copy SCREEN.BIN FLOPPY.BIN > NUL' \
    'SYNMIND.EXE /DEMO /DUMP=HARDDISK' \
    'copy SCREEN.BIN HARDDISK.BIN > NUL' \
    'SYNMIND.EXE /DEMO /DUMP=CDROM' \
    'copy SCREEN.BIN CDROM.BIN > NUL' \
    'SYNMIND.EXE /DEMO /DUMP=SETTINGS' \
    'copy SCREEN.BIN SETTINGS.BIN > NUL' \
    'SYNMIND.EXE > NOBAY.TXT' \
    "autotype -w 2 -p 0.3 $keys" \
    'SYNMIND.EXE /DEMO /DUMP=EXIT' \
    'copy SCREEN.BIN KEYS.BIN > NUL' \
    'exit'
} > "$conf"

echo "Building with Turbo Pascal 7 in DOSBox-X..."
# In a subshell: DOSBox-X can crash as it exits with no video, after the work is done
( SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$dosbox" -conf "$(native "$conf")" -fastlaunch -nomenu -exit \
  -time-limit 120 > "$out/dosbox.log" 2>&1 ) > /dev/null 2>&1 || true

show() { tr -d '\r' < "$1" 2> /dev/null | sed '/^$/d' || echo "(no $1)"; }
show "$out/BUILD.LOG"
if [ ! -f "$out/SYNMIND.EXE" ] || [ ! -f "$out/TESTS.EXE" ] || grep -q "Error " "$out/BUILD.LOG"; then
  echo "Build failed" >&2
  exit 1
fi
echo "--- tests"; show "$out/TESTS.TXT"
echo "--- version"; show "$out/VERSION.TXT"
echo "--- without a Bay"; show "$out/NOBAY.TXT"
grep -q " 0 failed" "$out/TESTS.TXT" || { echo "Tests failed" >&2; exit 1; }

# The scripted session's changes, on each tab when it ended
session=
for f in KEYS1 KEYS2 KEYS3 KEYS4 KEYS5; do
  session+=$(PYTHONIOENCODING=utf-8 "$python" "$repo/scripts/screen.py" "$out/$f.BIN" 2> /dev/null || true)
  session+=$'\n'
done
failed=
for expect in "Volume .* 70 " "L .* R 60 " "Playing     Voice coil 1991" \
              "Disc        QUAKE.ISO" "Next reset  DOSBENCH.IMG"; do
  grep -q "$expect" <<< "$session" || { echo "Keyboard session: no '$expect'" >&2; failed=1; }
done
if [ -n "$failed" ]; then
  echo "$session"
  echo "Keyboard session failed" >&2
  exit 1
fi
echo "--- keyboard session: as expected"

if [ -n "$run" ]; then
  conf="$out/run.conf"
  {
    printf '[sdl]\r\nautolock=false\r\n[dosbox]\r\ntitle=SynthMinder\r\n[autoexec]\r\n'
    printf '%s\r\n' "mount c \"$(native "$out")\"" 'c:' 'SYNMIND /DEMO'
  } > "$conf"
  "$dosbox" -conf "$(native "$conf")" -fastlaunch -nomenu > /dev/null 2>&1 &
fi
