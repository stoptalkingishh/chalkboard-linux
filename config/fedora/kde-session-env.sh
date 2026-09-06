#!/usr/bin/env sh

if [ "${USER:-}" = "chalkboard" ]; then
    export XDG_CONFIG_DIRS="/etc/xdg/chalkboard:${XDG_CONFIG_DIRS:-/etc/xdg}"
fi
