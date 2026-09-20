import AppKit
import CoreGraphics

// Minimal DTO adapter for the attributed upstream input transport.
struct FrameDTO { let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat }
struct ResolvedWindowDTO { let pid: Int32; let bundleID: String; let windowNumber: Int; let title: String; let frameAppKit: FrameDTO }
enum MouseButtonDTO { case left, right }
enum DesktopGeometry { static func desktopTop() -> CGFloat { NSScreen.screens.map(\.frame.maxY).max() ?? 0 } }

func routedTarget(pid: pid_t, window: CGWindowID, bounds: CGRect) throws -> RoutedClickTarget {
    let dto = ResolvedWindowDTO(pid: pid, bundleID: "com.blizzard.worldofwarcraft", windowNumber: Int(window),
        title: "WoW", frameAppKit: FrameDTO(x: bounds.minX, y: DesktopGeometry.desktopTop()-bounds.maxY,
                                          width: bounds.width, height: bounds.height))
    return RoutedClickTarget(window: dto, routing: try NativeWindowServerRoutingResolver().resolve(windowNumber: Int(window)))
}
