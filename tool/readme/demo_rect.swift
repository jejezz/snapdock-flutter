// Prints "x,y,w,h" (points, top-left origin) of a strip at the top centre of the primary
// display's visible area — where Snapdock's dock appears. tool/readme/demo.sh records it.
//
//   swift tool/readme/demo_rect.swift 760 150
import AppKit

let w = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "760") ?? 760
let h = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "150") ?? 150
let screen = NSScreen.screens[0]
let visible = screen.visibleFrame
let top = screen.frame.height - visible.maxY
let x = visible.minX + (visible.width - w) / 2
print("\(Int(x)),\(Int(top)),\(Int(w)),\(Int(h))")
