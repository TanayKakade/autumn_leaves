#!/bin/zsh
# Builds "Autumn Leaves.app" — a double-clickable Mac app.
# Usage: zsh make_app.sh
set -e
cd "${0:A:h}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Run: xcode-select --install"
  exit 1
fi

APP="Autumn Leaves.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O AutumnLeaves.swift -o "$APP/Contents/MacOS/AutumnLeaves"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Autumn Leaves</string>
    <key>CFBundleDisplayName</key>        <string>Autumn Leaves</string>
    <key>CFBundleIdentifier</key>         <string>com.autumnleaves.app</string>
    <key>CFBundleExecutable</key>         <string>AutumnLeaves</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>12.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS (especially Apple Silicon) is happy to run it
codesign --force --deep --sign - "$APP"

echo ""
echo "🍂 Done: $APP"
echo "Double-click it, or drag it into your Applications folder."
echo "Quit it from the 🍂 icon in the menu bar."
