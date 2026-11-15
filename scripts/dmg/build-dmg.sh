#!/bin/bash
# Builds the Baplet install DMG: the app, an Applications alias (made by the layout script),
# three links (the docs' install section; a page on the site that opens System Settings at
# Privacy & Security, where Open Anyway appears, since Finder won't open a settings link from a
# .webloc; and GitHub Sponsors) and a Finder window laid out over a background with the steps.
# If Finder can't lay out the window (it is driven by AppleScript, which can fail on a CI
# runner), the DMG is still built, just without the layout, and a warning is printed.
# Usage: scripts/dmg/build-dmg.sh <version> <path/to/Baplet.app> <output.dmg>

set -euo pipefail

version="$1"
app="$2"
output="$3"
here="$(cd "$(dirname "$0")" && pwd)"
volume_name="Baplet $version"
work="$(mktemp -d)"
stage="$work/stage"
trap 'hdiutil detach "/Volumes/$volume_name" -quiet -force 2>/dev/null || true; rm -rf "$work"' EXIT

write_link() {
    local name="$1" url="$2"
    cat > "$stage/$name.webloc" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>URL</key>
	<string>$url</string>
</dict>
</plist>
EOF
    xcrun SetFile -a E "$stage/$name.webloc"
}

mkdir -p "$stage/.background"
cp -R "$app" "$stage/"
tiffutil -cathidpicheck "$here/background.png" "$here/background@2x.png" -out "$stage/.background/background.tiff" >/dev/null 2>&1
write_link "Installation help" "https://baplet.konkord.io/docs.html#install"
write_link "Open Privacy & Security" "https://baplet.konkord.io/open-privacy-security.html"
write_link "Sponsor Baplet" "https://github.com/sponsors/lazee"
swift "$here/set-icon.swift" "$stage/Installation help.webloc" --default-browser \
    || echo "warning: could not set the Installation help icon."
swift "$here/set-icon.swift" "$stage/Open Privacy & Security.webloc" "/System/Applications/System Settings.app" \
    || echo "warning: could not set the Privacy & Security icon."
swift "$here/set-icon.swift" "$stage/Sponsor Baplet.webloc" --image "$here/sponsor-icon.png" \
    || echo "warning: could not set the Sponsor icon."

hdiutil detach "/Volumes/$volume_name" -quiet -force 2>/dev/null || true
hdiutil create -quiet -volname "$volume_name" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"

volume="/Volumes/$volume_name"
if osascript "$here/layout.applescript" "$volume_name"; then
    for _ in $(seq 1 20); do
        [ -s "$volume/.DS_Store" ] && break
        sleep 0.5
    done
    sleep 2
    echo "Laid out the DMG window."
    swift "$here/set-icon.swift" "$volume/Applications" /Applications \
        || echo "warning: could not set the Applications icon."
else
    echo "warning: Finder could not lay out the DMG window; building it without the layout."
    [ -e "$volume/Applications" ] || ln -s /Applications "$volume/Applications"
fi
rm -rf "$volume/.fseventsd"
sync
hdiutil detach "/Volumes/$volume_name" -quiet

mkdir -p "$(dirname "$output")"
rm -f "$output"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$output"
