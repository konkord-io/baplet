-- Lays out the mounted, writable Baplet DMG in Finder: a fixed icon-view window (660x520 of content below Finder's title and tab bar) with
-- no toolbar, the background with the install steps, and every item where the background
-- expects it (positions are icon centres and must match scripts/dmg/make-background.py).
-- Applications is a Finder alias rather than a symlink: Finder draws a symlink on a disk image
-- with a blank icon, an alias with the real folder icon. Finder stores all of this in the
-- volume's .DS_Store, so it shows the same on every Mac.
-- Usage: osascript layout.applescript "<volume name>"

on run argv
	set volumeName to item 1 of argv
	tell application "Finder"
		make new alias file at disk volumeName to (POSIX file "/Applications" as alias) with properties {name:"Applications"}
		tell disk volumeName
			open
			delay 1
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			delay 1
			set the bounds of container window to {200, 120, 860, 709}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 72
			set text size of viewOptions to 13
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item "Baplet.app" of container window to {190, 135}
			set position of item "Applications" of container window to {470, 135}
			set position of item "Installation help.webloc" of container window to {150, 400}
			set position of item "Open Privacy & Security.webloc" of container window to {330, 400}
			set position of item "Sponsor Baplet.webloc" of container window to {510, 400}
			close
			open
			set the bounds of container window to {200, 120, 860, 709}
			update without registering applications
			delay 3
			close
		end tell
	end tell
end run
