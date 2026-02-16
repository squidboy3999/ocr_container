#!/usr/bin/env bash
set -Eeuo pipefail

IN_DIR="${IN_DIR:-/data/in}"
OUT_DIR="${OUT_DIR:-/data/out}"
DONE_DIR="${DONE_DIR:-/data/done}"
FAIL_DIR="${FAIL_DIR:-/data/fail}"

OCR_LANG="${OCR_LANG:-eng}"
OPTIMIZE="${OPTIMIZE:-3}"
JOBS_PER_FILE="${JOBS_PER_FILE:-2}"
SCAN_INTERVAL="${SCAN_INTERVAL:-10}"
USE_INOTIFY="${USE_INOTIFY:-1}"
OUTPUT_TYPE="${OUTPUT_TYPE:-pdfa}"
SIDECAREXT="${SIDECAREXT:-.txt}"

PROC_DIR="$IN_DIR/.processing"
mkdir -p "$IN_DIR" "$OUT_DIR" "$DONE_DIR" "$FAIL_DIR" "$PROC_DIR"

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

process_one() {
  local src="$1"
  local base name tmp
  base="$(basename -- "$src")"
  name="${base%.*}"
  tmp="$PROC_DIR/$base"

  # Claim the file atomically by moving it to our processing subdir
  if ! mv -n -- "$src" "$tmp"; then
    log "Skip (already grabbed?): $src"
    return 0
  fi

  log "Processing: $base"

  # Output targets
  local out_pdf="$OUT_DIR/$name.pdf"
  local sidecar="$OUT_DIR/$name$SIDECAREXT"

  # Run OCR
  if ocrmypdf \
      --skip-text \
      --deskew \
      --rotate-pages \
      --clean \
      --optimize "$OPTIMIZE" \
      --output-type "$OUTPUT_TYPE" \
      -l "$OCR_LANG" \
      --sidecar "$sidecar" \
      --jobs "$JOBS_PER_FILE" \
      "$tmp" "$out_pdf"; then
    log "Success: $base -> $(basename "$out_pdf"), sidecar $(basename "$sidecar")"
    mv -f -- "$tmp" "$DONE_DIR/$base"
  else
    log "ERROR: OCR failed for $base"
    mv -f -- "$tmp" "$FAIL_DIR/$base" || true
    # Remove any partial outputs to avoid confusion
    rm -f -- "$out_pdf" "$sidecar" || true
  fi
}

batch_once() {
  shopt -s nullglob nocaseglob
  local found=0
  for f in "$IN_DIR"/*.pdf "$IN_DIR"/*.PDF; do
    found=1
    process_one "$f"
  done
  shopt -u nullglob nocaseglob
  return $found
}

# Handle graceful stop
trap 'log "Shutting down..."; exit 0' SIGTERM SIGINT

log "Watcher started."
log "Settings: lang=$OCR_LANG, jobs/file=$JOBS_PER_FILE, optimize=$OPTIMIZE, output_type=$OUTPUT_TYPE, sidecar=$SIDECAREXT"

# Process any existing files first
batch_once || true

if [[ "$USE_INOTIFY" == "1" ]] && command -v inotifywait >/dev/null 2>&1; then
  log "Using inotify to watch: $IN_DIR"
  # Watch for created/moved PDFs; still run a batch if multiple arrive quickly
  inotifywait -m -e close_write,create,move --format '%w%f' "$IN_DIR" | while read -r path; do
    case "${path,,}" in
      *.pdf) process_one "$path" ;;
    esac
  done
else
  log "Polling every ${SCAN_INTERVAL}s (inotify disabled or missing)"
  while :; do
    batch_once || sleep "$SCAN_INTERVAL"
  done
fi
