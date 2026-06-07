#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AgentDock"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
OUTPUT_DIR="${1:-$HOME/Documents}"
DMG_NAME="${2:-$APP_NAME.dmg}"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
VOLUME_NAME="$APP_NAME"
SIGN_IDENTITY="${AGENTDOCK_SIGN_IDENTITY:--}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
fi

"$ROOT_DIR/script/build_and_run.sh" --package-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle at $APP_BUNDLE" >&2
  exit 1
fi

/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

STAGE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cp -R "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
cat >"$STAGE_DIR/README.txt" <<README
AgentDock

Install:
1. Drag AgentDock.app to Applications.
2. Open AgentDock from Applications.

This local DMG is ad-hoc signed unless AGENTDOCK_SIGN_IDENTITY is set to a Developer ID Application identity.
For first launch on another Mac, macOS Gatekeeper may require right-click > Open or Developer ID notarization.
README

rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
