#!/bin/bash
set -euo pipefail

# ---- PATHS (edit if needed)
RECOVERY="/Volumes/2TB Ext Mac/Organized"
LIB_MUSIC_CONCERTS="/Volumes/My Book Duo/ServerMedia/Videos/Music_Concerts"
LIB_PHISH="/Volumes/My Book Duo/ServerMedia/Videos/Phish_Video"
QUARANTINE="/Volumes/2TB Ext Mac/_Quarantine"
STAGING="/Volumes/2TB Ext Mac/_Newly_Saved"
LOG="/Volumes/2TB Ext Mac/_dedupe_sort_$(date +%Y%m%d_%H%M%S).log"

# ---- EXTENSIONS we care about
EXTS='mp4|mkv|mov|m4v|avi'

# ---- dependency checks (jdupes, ffprobe, mediainfo)
need() { command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
need ffprobe; need jdupes; need mediainfo

mkdir -p "$QUARANTINE" "$STAGING"

echo "== Quarantine corrupt files ==" | tee -a "$LOG"
# Find & move corrupt videos from RECOVERY to QUARANTINE
# (ffprobe returns non-zero on broken containers/streams)
while IFS= read -r f; do
  if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
        -of csv=p=0 "$f" > /dev/null 2>&1; then
    echo "CORRUPT >> $f" | tee -a "$LOG"
    mv -n "$f" "$QUARANTINE/"
  fi
done < <(find "$RECOVERY" -type f -iregex ".*\.($EXTS)$")

echo "== Delete exact dupes from RECOVERY (keep Library) ==" | tee -a "$LOG"
# Compare RECOVERY against both library roots; delete dupes only from RECOVERY
jdupes -r -X size+hash -dN "$RECOVERY" "$LIB_MUSIC_CONCERTS" "$LIB_PHISH" | tee -a "$LOG"

echo "== Stage remaining unique files from RECOVERY ==" | tee -a "$LOG"
# Move what’s left in RECOVERY to a staging area
while IFS= read -r f; do
  rel="$(basename "$f")"
  echo "STAGE >> $f" | tee -a "$LOG"
  mv -n "$f" "$STAGING/$rel"
done < <(find "$RECOVERY" -type f -iregex ".*\.($EXTS)$")

echo "== Auto-sort staged files to artist folders ==" | tee -a "$LOG"

# Map of artist keywords -> destination folder name (expandable)
declare -A MAP=(
  ["phish"]="Phish"
  ["dead & company"]="Dead & Company"
  ["dead and company"]="Dead & Company"
  ["grateful dead"]="Grateful Dead"
  ["jgb"]="JGB"
  ["allman brothers"]="Allman Brothers Band"
  ["daniel donato"]="Daniel Donato"
  ["goose"]="Goose"
  ["jrad"]="JRAD"
  ["billy strings"]="Billy Strings"
  ["taylor swift"]="Taylor Swift"
  ["vulfpeck"]="Vulfpeck"
  ["oysterhead"]="Oysterhead"
  ["tedeschi trucks"]="Tedeschi Trucks Band"
  ["ween"]="Ween"
  ["khruangbin"]="Khruangbin"
  ["spafford"]="Spafford"
  ["greensky"]="Greensky Bluegrass"
  ["led zeppelin"]="Led Zeppelin"
)

normalize() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

route_file() {
  local f="$1"
  local lcf="$(normalize "$f")"
  local destBase="$LIB_MUSIC_CONCERTS"

  # Special-case Phish into the Phish_Video tree if present
  if [[ "$lcf" =~ phish ]]; then destBase="$LIB_PHISH"; fi

  local artistFolder=""
  for key in "${!MAP[@]}"; do
    if grep -qiE "\b${key}\b" <<<"$lcf"; then
      artistFolder="${MAP[$key]}"
      break
    fi
  done

  if [[ -z "$artistFolder" ]]; then
    # Couldn’t detect artist — leave in staging and log
    echo "UNMATCHED >> $(basename "$f")" | tee -a "$LOG"
    return
  fi

  local dest="$destBase/$artistFolder"
  mkdir -p "$dest"

  # Don’t overwrite; if exists, append a counter
  local base="$(basename "$f")"
  local name="${base%.*}"
  local ext="${base##*.}"
  local target="$dest/$base"
  local n=1
  while [[ -e "$target" ]]; do
    target="$dest/${name} ($n).$ext"
    ((n++))
  done

  echo "MOVE >> $f  ==>  $target" | tee -a "$LOG"
  mv -n "$f" "$target"
}

# Walk staging and route
while IFS= read -r f; do
  route_file "$f"
done < <(find "$STAGING" -type f -iregex ".*\.($EXTS)$")

echo "== Done =="
echo "Quarantine: $QUARANTINE"
echo "Unmatched (left in staging): $STAGING"
echo "Log: $LOG"
