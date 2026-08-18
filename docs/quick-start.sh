#!/bin/bash
# holmes quick-start
# run as your normal user — do NOT use sudo
#   bash /home/house/projects/holmes/docs/quick-start.sh

set -uo pipefail

HOLMES_DIR="${HOLMES_DIR:-/home/house/projects/holmes}"
HOLMES="${HOLMES_DIR}/core/bin"
TESTS="${HOLMES_DIR}/core/tests"
EDITOR_DIR="${HOME:-/home/house}/editor"
FLUTTER_DIR="${HOME:-/home/house}/flutter-sdk"

ok()   { echo -e "  \e[32m✓ $1\e[0m"; }
err()  { echo -e "  \e[31m✗ $1\e[0m"; }
step() { echo -e "\n\e[36m▶ $1\e[0m"; }

if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
  err "Do NOT run this script as root — run as your normal user:"
  echo "    bash /home/house/projects/holmes/docs/quick-start.sh"
  exit 1
fi

step "Python core tests"
chmod +x "$HOLMES"/*
PYTHONPATH="$HOLMES" python3 "$TESTS/test_core.py" && ok "core tests pass"

step "Flutter analyze (editor)"
if [ -d "$EDITOR_DIR" ]; then
  export PATH="${FLUTTER_DIR}/bin:${PATH}"
  cd "$EDITOR_DIR"
  flutter analyze 2>&1 | grep -q "error" \
    && err "flutter errors found (see above)" \
    || ok "no HolmeS-related errors"
else
  err "editor not found at $EDITOR_DIR"
fi

step "Jellyfin proxy"
if [ -f "${HOLMES_DIR}/jellyfin/holmes_jellyfin_proxy.py" ]; then
  python3 -c "import flask" && ok "flask available" || err "flask not installed"
  python3 -m py_compile "${HOLMES_DIR}/jellyfin/holmes_jellyfin_proxy.py" && ok "proxy syntax ok"
else
  err "proxy not found"
fi

step "Nextcloud app"
APP="${HOLMES_DIR}/nextcloud/apps/holmesviewer"
[ -d "$APP" ] && ok "nextcloud app ready — cp to <NC>/apps/ && occ app:enable holmesviewer" \
                || err "nextcloud app not found"

step "E2E round-trip demo"
DEMO=$(mktemp -d)
# write a minimal 1x1 PNG
printf '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1F\x15\xC4\x89\x00\x00\x00\x0A\x49\x44\x41\x54\x78\x9C\x63\x00\x01\x00\x00\x05\x00\x01\x0D\x0A\x2D\xB4\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82' > "$DEMO/img.png"
# convert to .holmes
PYTHONPATH="$HOLMES" python3 "$HOLMES/holmes" "$DEMO" -o "$DEMO"
HLM=$(ls "$DEMO"/*.holmes | head -1)
# verify
PYTHONPATH="$HOLMES" python3 "$HOLMES/holmes-verify" "$HLM" && ok ".holmes verified"
# extract + compare
PYTHONPATH="$HOLMES" python3 "$HOLMES/holmes-extract" "$HLM" "$DEMO/restored.png"
if diff -q "$DEMO/img.png" "$DEMO/restored.png" > /dev/null 2>&1; then
  ok "e2e round-trip match"
else
  err "e2e round-trip mismatch"
fi
rm -rf "$DEMO"

echo ""
echo -e "\e[32m══ holmes quick-start complete ═══════════════════════════════════\e[0m"
echo ""
echo "next steps:"
echo "  1. convert media : $HOLMES ~/Pictures -o ~/holmes_out"
echo "  2. build editor  : cd $EDITOR_DIR && flutter build linux --release"
echo "  3. jellyfin proxy: python3 ${HOLMES_DIR}/jellyfin/holmes_jellyfin_proxy.py"
echo "  4. nextcloud app : occ app:enable holmesviewer"
echo ""
