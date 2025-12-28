#!/usr/bin/env nix-shell
#!nix-shell -i bash -p depotdownloader coreutils gnugrep gnused

APP_ID="$1"
DEPOT_ID="$2"
PACKAGE_PATH="$3"

MANIFEST_ID="$(
    curl -s "https://api.steamcmd.net/v1/info/$APP_ID" \
    | jq -r \
    --arg appId "$APP_ID" \
    --arg depotId "$DEPOT_ID" \
    '.data[$appId].depots[$depotId].manifests.public.gid'
)"

sed -i 's/manifestId = "[0-9]*"/manifestId = "'"$MANIFEST_ID"'"/' "$PACKAGE_PATH"