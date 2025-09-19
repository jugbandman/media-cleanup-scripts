#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
SECONDARY="/Volumes/2TB Ext Mac/Organized"  # recovery
LIB_CONCERTS="/Volumes/My Book Duo/ServerMedia/Videos/Music_Concerts"
LIB_PHISH="/Volumes/My Book Duo/ServerMedia/Videos/Phish_Video"

STAGING="/Volumes/2TB Ext Mac/_Newly_Saved_Secondary"
QUARANTINE="/Volumes/2TB Ext Mac/_Quarantine"

# Set to 1 to automatically move renamed uniques from STAGING into the Plex library
AUTO_SORT=1

EXTS='mp4|mkv|mov|m4v|avi'
LOG="/Volumes/2TB Ext Mac/_executor_$(date +%Y%m%d_%H%M%S).log"

need(){ command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
need ffprobe; need jdupes; need mediainfo

mkdir -p "$STAGING" "$QUARANTINE"
: > "$LOG"; echo "LOG FILE: $LOG" | tee -a "$LOG"
log(){ echo "$@" | tee -a "$LOG"; }

echo "This WILL modify files:"
echo " - Delete dupes from SECONDARY when also in LIBRARY"
echo " - Move remaining files to STAGING on 2TB with safe rename"
[ "$AUTO_SORT" = "1" ] && echo " - Auto-sort STAGING into Plex library"
read -r -p "Type YES to proceed: " OK
[ "$OK" = "YES" ] || { echo "Aborted."; exit 1; }

normalize(){ tr '[:upper:]' '[:lower:]' <<<"$1"; }
safe_target_path(){ local dir="$1"; local base="$2"; mkdir -p "$dir"; local n=1; local name="${base%.*}"; local ext="${base##*.}"; local t="$dir/$base"; while [[ -e "$t" ]]; do t="$dir/${name} ($n).$ext"; ((n++)); done; echo "$t"; }
detect_artist(){
  local s="$(normalize "$1")"
  declare -A MAP=(
    ["phish"]="Phish" ["dead & company"]="Dead & Company" ["dead and company"]="Dead & Company"
    ["grateful dead"]="Grateful Dead" ["jgb"]="JGB" ["daniel donato"]="Daniel Donato"
    ["goose"]="Goose" ["jrad"]="JRAD" ["billy strings"]="Billy Strings"
    ["tedeschi trucks"]="Tedeschi Trucks Band" ["vulfpeck"]="Vulfpeck" ["ween"]="Ween"
    ["khruangbin"]="Khruangbin" ["spafford"]="Spafford" ["greensky"]="Greensky Bluegrass"
    ["oysterhead"]="Oysterhead" ["allman brothers"]="Allman Brothers Band" ["led zeppelin"]="Led Zeppelin"
  )
  for k in "${!MAP[@]}"; do grep -qiE "\b${k}\b" <<<"$s" && { echo "${MAP[$k]}"; return; }; done
  echo ""
}
detect_date(){
  local s="$1"
  if [[ "$s" =~ ([12][0-9]{3})[-._]([01][0-9])[-._]([0-3][0-9]) ]]; then printf "%04d-%02d-%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; return; fi
  if [[ "$s" =~ ([01][0-9])[-._]([0-3][0-9])[-._]([12][0-9]{3}) ]]; then printf "%04d-%02d-%02d" "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return; fi
  if [[ "$s" =~ ([01]?[0-9])[._-]([0-3]?[0-9])[._-]([0-9]{2}) ]]; then local yy="${BASH_REMATCH[3]}"; local yyyy=$((2000+10#$yy)); printf "%04d-%02d-%02d" "$yyyy" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return; fi
  echo ""
}
ff_meta(){ ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of default=nw=1:nk=1 "$1" 2>/dev/null | tr '\n' ' '; }
rename_into(){
  local src="$1" ; local destdir="$2"
  local artist="$(detect_artist "$src")"; [ -z "$artist" ] && artist="Unknown"
  local date="$(detect_date "$src")"
  local m; m=$(ff_meta "$src"); read -r w h codec <<<"$m"
  local res=""; [ -n "${h:-}" ] && res="${h}p"
  local codec_tag=""; [[ "${codec:-}" =~ (hevc|h265) ]] && codec_tag="HEVC" || { [[ "${codec:-}" =~ (h264|avc) ]] && codec_tag="H264" || codec_tag="$(tr '[:lower:]' '[:upper:]' <<<"${codec:-UNK}")"; }
  local base="$(basename "$src")"
  local new="$artist"; [ -n "$date" ] && new="$new.$date"; [ -n "$res" ] && new="$new.$res"; [ -n "$codec_tag" ] && new="$new.$codec_tag"
  new="${new}.${base}"; new="${new// /_}"
  local target="$(safe_target_path "$destdir" "$new")"
  mv -n "$src" "$target"
  log "RENAME+MOVE >> $src  -->  $target"
  echo "$target"
}

# A) Quarantine corrupt (SECONDARY)
log "== Quarantine corrupt in SECONDARY =="
while IFS= read -r f; do
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" >/dev/null 2>&1 || { mv -n "$f" "$QUARANTINE/"; log "QUARANTINE >> $f"; }
done < <(find "$SECONDARY" -type f -iregex ".*\.($EXTS)$")

# B) Delete dupes from SECONDARY when in LIB (LIB first so -dN keeps Library)
log "== Delete SECONDARY dupes that exist in LIBRARY =="
jdupes -r -X onlyext:mp4,mkv,mov,m4v,avi -dN "$LIB_CONCERTS" "$LIB_PHISH" "$SECONDARY" | tee -a "$LOG"

# C) Stage remaining files with rename into 2TB STAGING
log "== Stage remaining files from SECONDARY (with rename) =="
find "$SECONDARY" -type f -iregex ".*\.($EXTS)$" | while IFS= read -r f; do
  [ -f "$f" ] || continue
  rename_into "$f" "$STAGING" >/dev/null
done

# D) Auto-sort from 2TB STAGING into Plex library (optional)
if [ "$AUTO_SORT" = "1" ]; then
  log "== Auto-sort STAGING into Plex artist folders =="
  find "$STAGING" -type f -iregex ".*\.($EXTS)$" | while IFS= read -r f; do
    artist="$(detect_artist "$f")"
    if [ -z "$artist" ] || [ "$artist" = "Unknown" ]; then
      log "UNMATCHED (left in STAGING) >> $(basename "$f")"
      continue
    fi
    destBase="$LIB_CONCERTS"; if grep -qiE "\bphish\b" <<<"$(normalize "$artist")"; then destBase="$LIB_PHISH"; fi
    destdir="$destBase/$artist"
    target="$(safe_target_path "$destdir" "$(basename "$f")")"
    mv -n "$f" "$target"
    log "MOVE TO LIBRARY >> $(basename "$f")  -->  $target"
  done
else
  log "AUTO_SORT disabled; files remain in STAGING: $STAGING"
fi

log "== DONE =="
log "Staging leftovers: $STAGING"
log "Quarantine:       $QUARANTINE"
