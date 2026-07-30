#!/bin/bash
# Copy the Lightroom plugin into place.
#
# Lightroom Classic reads plug-ins from a few locations; this uses the per-user
# Modules folder, which needs no admin rights and survives Lightroom updates.
set -e

PLUGIN="irgconverter.lrplugin"
SOURCE="$(cd "$(dirname "$0")" && pwd)/$PLUGIN"
DEST_DIR="$HOME/Library/Application Support/Adobe/Lightroom/Modules"
DEST="$DEST_DIR/$PLUGIN"

if [ ! -d "$SOURCE" ]; then
    echo "error: $PLUGIN not found next to this script" >&2
    exit 1
fi

if [ ! -d "/Applications/IRGConverter.app" ]; then
    echo "note: IRGConverter.app is not in /Applications."
    echo "      The plugin looks there first, then in ~/Applications, then next to"
    echo "      this repository, then asks Spotlight. If none of those find it, set"
    echo "      the path in Lightroom under File > Plug-in Manager."
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"

echo "Installed: $DEST"
echo
echo "In Lightroom Classic:"
echo "  1. File > Plug-in Manager should now list \"IRGConverter\"."
echo "     If not, click Add and choose the folder above."
echo "  2. Select photos, then Library > Plug-in Extras > Open in IRGConverter."
