#!/usr/bin/env nix-shell
#!nix-shell -i bash --expr 'with import <nixpkgs> { config.allowUnfree = true; }; runCommand "dummy" { buildInputs = [ steamcmd coreutils gnugrep gnused ]; } ""'

APP_ID="$1"
DEPOT_ID="$2"
PACKAGE_PATH="$3"

MANIFEST_ID="$(
    steamcmd +login anonymous \
    +app_info_print "$APP_ID" \
    +quit \
    | grep -A 20 "\"$DEPOT_ID\"" \
    | grep '"gid"' | head -n 1 | sed 's/[^0-9]//g'
)"

sed -i 's/manifestId = "[0-9]*"/manifestId = "'"$MANIFEST_ID"'"/' "$PACKAGE_PATH"