#!/usr/bin/env bash

set -Eeuo pipefail

STATE_DIR="${CHALKBOARD_STATE_DIR:-/var/lib/chalkboard}"

if [[ "${USER:-}" != chalkboard || ! -f "$STATE_DIR/gcompris-mode-enabled" ]]; then
  logger -t chalkboard-gcompris "refusing session for user ${USER:-unknown}: mode is not enabled"
  exit 1
fi

export QT_QPA_PLATFORM=wayland

# -s retains the credential-gated local-console recovery path. Cage otherwise
# exposes no shell, launcher, panel, window switcher, or additional clients.
exec /usr/bin/cage -s -- /usr/bin/gcompris-qt --fullscreen --enable-kioskmode
