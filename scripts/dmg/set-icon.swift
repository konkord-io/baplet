// Gives a file in the DMG a custom Finder icon copied from another file or app, so Finder
// never has to look it up: it draws the Applications alias on a disk image as a blank square,
// and web links as generic "HTTP" pages.
// Usage: swift set-icon.swift <file to change> <file or app whose icon to use>
//        swift set-icon.swift <file to change> --default-browser
//        swift set-icon.swift <file to change> --image <png to use as the icon>

import AppKit

/// Copies the chosen icon onto the target file and exits non-zero if Finder refuses it.
func main() {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 || (arguments.count == 4 && arguments[2] == "--image") else {
        FileHandle.standardError.write(Data("usage: set-icon.swift <target> <source | --default-browser | --image <png>>\n".utf8))
        exit(2)
    }
    let target = arguments[1]
    let icon: NSImage
    if arguments[2] == "--image" {
        guard let image = NSImage(contentsOfFile: arguments[3]) else {
            FileHandle.standardError.write(Data("could not read \(arguments[3])\n".utf8))
            exit(1)
        }
        icon = image
    } else if arguments[2] == "--default-browser" {
        let probe = URL(string: "https://example.com")!
        let browser = NSWorkspace.shared.urlForApplication(toOpen: probe)?.path ?? "/Applications/Safari.app"
        icon = NSWorkspace.shared.icon(forFile: browser)
    } else {
        icon = NSWorkspace.shared.icon(forFile: arguments[2])
    }
    guard NSWorkspace.shared.setIcon(downscaled(icon), forFile: target, options: []) else {
        FileHandle.standardError.write(Data("could not set the icon of \(target)\n".utf8))
        exit(1)
    }
}

/// Redraws the icon as a single 512-pixel image (256 points at Retina), so Finder stores one
/// modest size instead of every size up to 1024 pixels, which kept the DMG three times larger.
func downscaled(_ icon: NSImage) -> NSImage {
    let pixels = 512
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return icon }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: 256, height: 256))
    image.addRepresentation(rep)
    return image
}

main()
