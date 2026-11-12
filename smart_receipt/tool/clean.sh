#!/usr/bin/env bash
# Hapus artefak build dan cache yang bisa dibuat ulang.
#
# `flutter run`, `flutter test`, dan `flutter build` menulis 1-2 GB ke
# `build/` dan `.dart_tool/`. Keduanya di-.gitignore, jadi menghapusnya tidak
# kehilangan apa pun — perintah Flutter berikutnya akan membuatnya lagi.
#
#   bash tool/clean.sh          # artefak Flutter + sampah macOS
#   bash tool/clean.sh --all    # tambah Pods iOS dan cache Python
#
# Yang TIDAK dihapus: assets/, test_assets/struk/, dan ML/.cord_cache/
# (sumber data held-out, tidak bisa dibuat ulang tanpa unduh ulang CORD).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"

before=$(du -sh "$PROJECT_ROOT" 2>/dev/null | cut -f1)

remove() {
  if [ -e "$1" ]; then
    rm -rf "$1"
    echo "  dihapus: ${1#"$PROJECT_ROOT"/}"
  fi
}

echo "Membersihkan artefak build ..."
remove "$ROOT/build"
remove "$ROOT/.dart_tool"

if [ "${1:-}" = "--all" ]; then
  echo "Membersihkan cache platform dan Python ..."
  remove "$ROOT/ios/Pods"
  remove "$ROOT/ios/build"
  remove "$ROOT/macos/Pods"
  remove "$PROJECT_ROOT/ML/__pycache__"
  remove "$PROJECT_ROOT/ML/uts/__pycache__"
fi

find "$PROJECT_ROOT" -name ".DS_Store" -not -path "*/.git/*" -delete 2>/dev/null || true

after=$(du -sh "$PROJECT_ROOT" 2>/dev/null | cut -f1)
echo
echo "Ukuran repo: $before -> $after"
echo "Jalankan 'flutter pub get' sebelum perintah Flutter berikutnya."
