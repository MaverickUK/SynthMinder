#!/usr/bin/env bash
# Record the README demo of SynthMinder running in DOSBox-X, against the
# pretend Bay, synth and Duo (SYNMIND /DEMO), as GameMinder's scripts/record-demo.sh
# does: DOSBox-X's AUTOTYPE presses the keys and DX-CAPTURE records the screen.
# No window is shown unless --show is given.
#
# Usage:   scripts/record-demo.sh [--show] path/to/SYNMIND.EXE
#          --show opens a DOSBox-X window to watch the recording
# Needs:   DOSBox-X (on PATH, or set DOSBOX_X), ffmpeg
# Output:  docs/synthminder-demo.gif and docs/synthminder-demo.mp4
#
# Use a Free Pascal build (the Turbo Pascal one stops with runtime error 200
# on fast CPUs): from a CI run, gh run download <run-id> -n synmind-dos
set -euo pipefail

# Hidden by default: no window or sound
hide="SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy"
if [ "${1:-}" = --show ]; then hide=; shift; fi
[ -n "${1:-}" ] || { echo "usage: $0 [--show] path/to/SYNMIND.EXE" >&2; exit 1; }

exe=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Windows paths for DOSBox-X when running in Git Bash, otherwise unchanged
native() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

dosbox=${DOSBOX_X:-$(command -v dosbox-x || true)}
for guess in "$HOME/scoop/apps/dosbox-x/current/dosbox-x.exe" "/c/Program Files/DOSBox-X/dosbox-x.exe"; do
  if [ -z "$dosbox" ] && [ -x "$guess" ]; then dosbox=$guess; fi
done
[ -n "$dosbox" ] || { echo "DOSBox-X not found - install it or set DOSBOX_X" >&2; exit 1; }

# Each key is pressed 1.2 s apart, "," adds an extra pause. Keep the autotype
# command under 255 characters, or DOSBox-X ignores the end of it, and don't
# start it with ",": every key after the first was lost (-w waits instead):
#   the Sound tab: up to another HDD Synth pack and play it, volume up, balance
#   right; help (F1); down to the Duo's other pack and play it; the Floppy tab
#   (Tab): MONKEY1.IMG into the Duo's B: (the B key); past the Hard disk tab to the
#   CD-ROM tab: down to QUAKE.ISO, Enter and confirm to put it in the drive, E and
#   confirm to eject it; the Settings tab: seek timing set to fdb05 from its
#   chooser, write-behind's question (with what it trades) left with Esc; Esc exits
keys="up up up enter , equals equals period , f1 , esc down down down down down enter , tab down down down down , b , , tab tab down enter , enter , e , enter , tab enter down down down down enter , down down down down enter , esc , esc"

for attempt in 1 2 3; do
  rm -rf "$work/c" "$work/capture"
  mkdir -p "$work/c" "$work/capture"
  cp "$exe" "$work/c/SYNMIND.EXE"
  env $hide "$dosbox" -fastlaunch -nomenu -time-limit 180 \
    -set "dosbox captures=$(native "$work/capture")" \
    -c "mount c \"$(native "$work/c")\"" -c "c:" -c "cls" \
    -c "autotype -w 3 -p 1.2 $keys" \
    -c "dx-capture /v SYNMIND.EXE /DEMO" > "$work/dosbox.log" 2>&1 || true
  if grep -q "Stopped capturing video" "$work/dosbox.log"; then break; fi
  echo "DOSBox-X stopped before the recording finished (attempt $attempt)" >&2
  [ "$attempt" -lt 3 ] || { cat "$work/dosbox.log" >&2; exit 1; }
done

avi=$(ls "$work"/capture/*.avi)
mkdir -p "$repo/docs"

# VGA text mode is captured at 720x400 but displayed at 4:3
ffmpeg -v error -y -i "$avi" -an -vf "scale=960:720:flags=neighbor" \
  -c:v libx264 -preset slow -crf 18 -tune animation -pix_fmt yuv420p -movflags +faststart \
  "$repo/docs/synthminder-demo.mp4"
ffmpeg -v error -y -i "$avi" \
  -vf "fps=8,scale=720:540:flags=neighbor,split[a][b];[a]palettegen=max_colors=32:stats_mode=full[p];[b][p]paletteuse=dither=none" \
  "$repo/docs/synthminder-demo.gif"

ls -lh "$repo/docs/synthminder-demo".*
