import CoreGraphics
import Foundation

/// Prints the id of the frontmost on-screen window owned by the process whose PID is the first
/// argument (the highest window level, then the largest), or nothing when it has none yet.
/// Used by screenshots.sh to find the demo scene. Demo mode keeps a full-screen backdrop just
/// below the scene, so picking by level (not size) always returns the scene, never the backdrop.
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: Int, layer: Int, area: Double)?
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    guard area >= 100 * 100 else { continue }
    if let current = best, (layer, area) <= (current.layer, current.area) { continue }
    best = (id, layer, area)
}
if let best { print(best.id) }
