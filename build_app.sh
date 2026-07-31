#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="IRGConverter"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

# One source of truth for the version: the Swift constant the CLI also prints.
VERSION_FILE="$PROJECT_DIR/Sources/IRGConverterCore/Version.swift"
VERSION="$(sed -n 's/.*let current = "\([^"]*\)".*/\1/p' "$VERSION_FILE")"
if [ -z "$VERSION" ]; then
    echo "error: could not read the version out of $VERSION_FILE" >&2
    exit 1
fi

# --zip additionally packages everything a download needs.
MAKE_ZIP=0
if [ "$1" = "--zip" ]; then MAKE_ZIP=1; fi

echo "Building $APP_NAME $VERSION..."

cd "$PROJECT_DIR"
swift build -c release --product "$APP_NAME"
swift build -c release --product irgconvert

# Ask SwiftPM where it put the binary rather than hardcoding a triple, so this
# works on Intel and on future toolchains.
BIN_PATH="$(swift build -c release --show-bin-path)"
BINARY="$BIN_PATH/$APP_NAME"

if [ ! -x "$BINARY" ]; then
    echo "error: expected binary not found at $BINARY" >&2
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# The command-line converter ships inside the bundle, so a scripted conversion needs
# nothing installed beyond the app.
cp "$BIN_PATH/irgconvert" "$APP_BUNDLE/Contents/MacOS/irgconvert"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.irg.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>NSHumanReadableCopyright</key>
    <string>Licensed under the GNU Affero General Public License v3.0.</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.irg.$APP_NAME.preset</string>
            <key>UTTypeDescription</key>
            <string>IRGConverter Preset</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>irgpreset</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <!-- So a Finder selection can be sent here with Open With, which is
                 how a batch of forty files gets in without an open panel. -->
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
                <string>public.camera-raw-image</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>IRGConverter Preset</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.irg.$APP_NAME.preset</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Ad-hoc sign so the bundle launches without a Gatekeeper prompt on the machine
# that built it.
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed; you may need to clear the quarantine attribute"

echo "Done: $APP_BUNDLE"
echo "     CLI at $APP_BUNDLE/Contents/MacOS/irgconvert"

if [ "$MAKE_ZIP" = "1" ]; then
    # A download that needs no further assembly: the app, the Lightroom plugin with
    # its installer, and the documents that say what the licence is and how to use
    # it. Built in a staging folder so the archive has one tidy top-level directory.
    STAGE="$PROJECT_DIR/dist/$APP_NAME-$VERSION"
    ARCHIVE="$PROJECT_DIR/dist/$APP_NAME-$VERSION.zip"
    echo "Packaging $ARCHIVE..."
    rm -rf "$STAGE" "$ARCHIVE"
    mkdir -p "$STAGE"
    # ditto rather than cp: it preserves the bundle's signature and resource forks.
    ditto "$APP_BUNDLE" "$STAGE/$APP_NAME.app"
    ditto "$PROJECT_DIR/LightroomPlugin" "$STAGE/LightroomPlugin"
    cp "$PROJECT_DIR/README.md" "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/CHANGELOG.md" "$STAGE/"
    # ditto -c -k writes a zip Finder and Gatekeeper are happy with; `zip` mangles
    # the bundle's symlinks. No --sequesterRsrc: it would add a __MACOSX folder of
    # metadata that nothing here needs, and the ad-hoc signature lives in the
    # bundle's own _CodeSignature folder rather than in extended attributes.
    (cd "$PROJECT_DIR/dist" && ditto -c -k --keepParent \
        "$APP_NAME-$VERSION" "$APP_NAME-$VERSION.zip")
    rm -rf "$STAGE"
    echo "Done: $ARCHIVE"
fi
