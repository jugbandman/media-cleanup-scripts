#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
SECONDARY="/Volumes/2TB Ext Mac/Organized"  # the only recovery source now
LIB_CONCERTS="/Volumes/My Book Duo/ServerMedia/Videos/Music_Concerts"
LIB_PHISH="/Volumes/My Book Duo/ServerMedia/Videos/Phish_Video"

OUTDIR="/Volumes/2TB Ext Mac/_Analyze_Reports"
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="$OUTDIR/report_$STAMP"
mkdir -p "$OUTDIR"
: > "$REPORT.summary.txt"

EXTS='mp4|mkv|mov|m4v|avi'

need(){ command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
need ffprobe; need jdupes; need mediainfo
log(){ echo "$@" | tee -a "$REPORT.summary.txt"; }

normalize(){ tr '[:upper:]' '[:lower:]' <<<"$1"; }
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

# ---------- Outputs ----------
CORR_SECONDARY="$REPORT.corrupt_secondary.txt"
DUP_LIB_SECONDARY="$REPORT.dupes_secondary_vs_library.txt"     # raw jdupes groups
UNIQ_SECONDARY="$REPORT.uniques_secondary.csv"                  # path,artist,date,res,codec,suggested_name,suggest_dest

touch "$CORR_SECONDARY" "$DUP_LIB_SECONDARY" "$UNIQ_SECONDARY"

# ---------- 1) Corruption (list only) ----------
log "== 1) Scan SECONDARY for corrupt files =="
while IFS= read -r f; do
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" >/dev/null 2>&1 || echo "$f" >> "$CORR_SECONDARY"
done < <(find "$SECONDARY" -type f -iregex ".*\.($EXTS)$")

# ---------- 2) Duplicates: SECONDARY vs LIBRARY (keep LIB) ----------
log "== 2) List dupes: SECONDARY vs LIBRARY (LIB kept, SECONDARY delete in executor) =="
jdupes -r -X onlyext:mp4,mkv,mov,m4v,avi "$LIB_CONCERTS" "$LIB_PHISH" "$SECONDARY" > "$DUP_LIB_SECONDARY" || true

# ---------- 3) Uniques + rename suggestions (executor will reconfirm) ----------
log "== 3) Suggest names and destinations for SECONDARY files (uniques to be confirmed in executor) =="
suggest(){
  local f="$1"
  local artist="$(detect_artist "$f")"; [ -z "$artist" ] && artist="Unknown"
  local date="$(detect_date "$f")"
  local m; m=$(ff_meta "$f"); read -r w h codec <<<"$m"
  local res=""; [ -n "${h:-}" ] && res="${h}p"
  local codec_tag=""; [[ "${codec:-}" =~ (hevc|h265) ]] && codec_tag="HEVC" || { [[ "${codec:-}" =~ (h264|avc) ]] && codec_tag="H264" || codec_tag="$(tr '[:lower:]' '[:upper:]' <<<"${codec:-UNK}")"; }
  local base="$(basename "$f")"
  local name="$artist"; [ -n "$date" ] && name="$name.$date"; [ -n "$res" ] && name="$name.$res"; [ -n "$codec_tag" ] && name="$name.$codec_tag"
  name="${name}.${base}"; name="${name// /_}"
  local destBase="$LIB_CONCERTS"; if grep -qiE "\bphish\b" <<<"$(normalize "$artist")"; then destBase="$LIB_PHISH"; fi
  local dest="$destBase/$artist"
  echo "\"$f\",\"$artist\",\"$date\",\"$res\",\"$codec_tag\",\"$name\",\"$dest\""
}
find "$SECONDARY" -type f -iregex ".*\.($EXTS)$" | while IFS= read -r f; do
  suggest "$f" >> "$UNIQ_SECONDARY"
done

# ---------- Summary ----------
log ""
log "Reports written:"
log "  Corrupt (Secondary):        $CORR_SECONDARY"
log "  Dupes (Secondary vs Library): $DUP_LIB_SECONDARY"
log "  Uniques (Secondary w/ suggestions): $UNIQ_SECONDARY"
