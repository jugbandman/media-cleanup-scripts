#!/bin/bash
set -euo pipefail

# ---- CONFIG: Update for your environment ----
RECOVERY="/Volumes/2TB Ext Mac/Organized"
LIB_MUSIC_CONCERTS="/Volumes/My Book Duo/ServerMedia/Videos/Music_Concerts"
LIB_PHISH="/Volumes/My Book Duo/ServerMedia/Videos/Phish_Video"
QUARANTINE="/Volumes/2TB Ext Mac/_Quarantine"
STAGING="/Volumes/2TB Ext Mac/_Newly_Saved"
LOG="/Volumes/2TB Ext Mac/_dedupe_sort_DRYRUN_$(date +%Y%m%d_%H%M%S).log"
# create log file up front and echo the path for sanity
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
echo "LOG FILE: $LOG" | tee -a "$LOG"

EXTS='mp4|mkv|mov|m4v|avi'

# ---- Dependencies ----
need() { command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
need ffprobe; need jdupes; need mediainfo

mkdir -p "$QUARANTINE" "$STAGING"

echo "== DRY RUN START ==" | tee -a "$LOG"

# 1. Corrupt file check (no moving, just log)
echo "== Checking for corrupt files in RECOVERY ==" | tee -a "$LOG"
while IFS= read -r f; do
  if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
        -of csv=p=0 "$f" > /dev/null 2>&1; then
    echo "WOULD QUARANTINE >> $f" | tee -a "$LOG"
  fi
done < <(find "$RECOVERY" -type f -iregex ".*\.($EXTS)$")

# 2. Exact duplicate check (no deletion, just log)
echo "== Checking for exact duplicates (Library vs Recovery) ==" | tee -a "$LOG"
jdupes -r "$RECOVERY" "$LIB_MUSIC_CONCERTS" "$LIB_PHISH" | tee -a "$LOG"

# 3. Unique file staging (no moving, just log)
echo "== Checking unique files in RECOVERY ==" | tee -a "$LOG"
while IFS= read -r f; do
  echo "WOULD STAGE >> $f" | tee -a "$LOG"
done < <(find "$RECOVERY" -type f -iregex ".*\.($EXTS)$")

# 4. Auto-sort preview
echo "== Preview auto-sort destinations ==" | tee -a "$LOG"

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

route_file_preview() {
  local f="$1"
  local lcf="$(normalize "$f")"
  local destBase="$LIB_MUSIC_CONCERTS"
  if [[ "$lcf" =~ phish ]]; then destBase="$LIB_PHISH"; fi

  local artistFolder=""
  for key in "${!MAP[@]}"; do
    if grep -qiE "\b${key}\b" <<<"$lcf"; then
      artistFolder="${MAP[$key]}"
      break
    fi
  done

  if [[ -z "$artistFolder" ]]; then
    echo "UNMATCHED (would stay in staging) >> $(basename "$f")" | tee -a "$LOG"
    return
  fi

  echo "WOULD MOVE >> $(basename "$f") --> $destBase/$artistFolder" | tee -a "$LOG"
}

while IFS= read -r f; do
  route_file_preview "$f"
done < <(find "$STAGING" -type f -iregex ".*\.($EXTS)$")

echo "== DRY RUN COMPLETE =="
echo "Log file: $LOG"
