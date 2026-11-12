#!/usr/bin/env bash
# Run the on-device OCR accuracy harness against a receipt set.
#
# The photos are deliberately not bundled into the APK: a release build should
# not carry ~70 MB of test images. They live in the repository under
# `test_assets/struk/`, and this script serves them over HTTP to the device for
# the duration of one test run. Pushing them to the device instead does not
# work, because `flutter test` reinstalls the APK and wipes the app's external
# storage directory.
#
#   bash tool/ocr_assets.sh list          # sets available, with sizes
#   bash tool/ocr_assets.sh run dev       # measure one set
#   bash tool/ocr_assets.sh serve         # just serve the sets (for manual use)
#
# Environment: DEVICE (default emulator-5554), PORT (default 8765).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/test_assets/struk"
PORT="${PORT:-8765}"
DEVICE="${DEVICE:-emulator-5554}"

# Sets are the directories that hold a ground_truth.json. The base directory
# (`test_assets/struk/`) is published as `dev` so the name matches the harness.
sets() {
  find "$SRC" -maxdepth 2 -name ground_truth.json | sort | while read -r file; do
    dir="$(dirname "$file")"
    name="$(basename "$dir")"
    [ "$dir" = "$SRC" ] && name="dev"
    printf '%s\t%s\n' "$name" "$dir"
  done
}

cmd_list() {
  echo "Sets under test_assets/struk:"
  while IFS=$'\t' read -r name dir; do
    [ -z "$name" ] && continue
    count=$(find "$dir" -maxdepth 1 -name '*.jpg' | wc -l | tr -d ' ')
    size=$(find "$dir" -maxdepth 1 -name '*.jpg' -exec du -ch {} + | tail -1 | cut -f1)
    printf '  %-10s %2s receipts  %s\n' "$name" "$count" "$size"
  done < <(sets)
}

test_file_for() {
  case "$1" in
    dev)       echo "integration_test/ocr_real_receipts_test.dart" ;;
    heldout)   echo "integration_test/ocr_heldout_test.dart" ;;
    heldout_b) echo "integration_test/ocr_heldout_b_test.dart" ;;
    heldout_c) echo "integration_test/ocr_heldout_c_test.dart" ;;
    heldout_d) echo "integration_test/ocr_heldout_d_test.dart" ;;
    *)         return 1 ;;
  esac
}

# A directory where every set appears under its published name, so the harness
# can request `dev/ground_truth.json` even though the dev set lives at the root
# of test_assets/struk. Symlinks keep this free.
stage_sets() {
  local stage
  stage="$(mktemp -d)"
  while IFS=$'\t' read -r name dir; do
    [ -z "$name" ] && continue
    ln -s "$dir" "$stage/$name"
  done < <(sets)
  printf '%s\n' "$stage"
}

cmd_run() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "Usage: bash tool/ocr_assets.sh run <set>" >&2
    cmd_list >&2
    exit 1
  fi
  local test_file
  if ! test_file="$(test_file_for "$name")"; then
    echo "Unknown set '$name'." >&2
    cmd_list >&2
    exit 1
  fi

  local stage
  stage="$(stage_sets)"
  python3 -m http.server "$PORT" --directory "$stage" --bind 127.0.0.1 >/dev/null 2>&1 &
  local server=$!
  # shellcheck disable=SC2064
  trap "kill $server 2>/dev/null || true; wait $server 2>/dev/null || true; rm -rf '$stage'" EXIT

  for _ in $(seq 1 50); do
    if curl -sf "http://127.0.0.1:$PORT/$name/ground_truth.json" >/dev/null; then
      break
    fi
    sleep 0.1
  done

  ( cd "$ROOT" && flutter test "$test_file" -d "$DEVICE" \
      --dart-define="OCR_HARNESS_URL=http://10.0.2.2:$PORT" )
}

cmd_serve() {
  local stage
  stage="$(stage_sets)"
  trap "rm -rf '$stage'" EXIT
  echo "Serving $SRC on http://127.0.0.1:$PORT (device sees 10.0.2.2:$PORT)"
  exec python3 -m http.server "$PORT" --directory "$stage" --bind 127.0.0.1
}

case "${1:-}" in
  list)  cmd_list ;;
  run)   cmd_run "${2:-}" ;;
  serve) cmd_serve ;;
  *)
    echo "Usage: bash tool/ocr_assets.sh {list|run <set>|serve}" >&2
    exit 1
    ;;
esac
