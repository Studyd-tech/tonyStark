import AppKit
import ApplicationServices
import Carbon.HIToolbox
import GestureCore

struct Desktop {
    let ids: [CGDirectDisplayID]
    let displays: [CGRect]
    let bounds: CGRect
    let signature: String

    init() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var activeIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &activeIDs, &count)
        ids = Array(activeIDs.prefix(Int(count)))
        displays = ids.map { CGDisplayBounds($0) }
        bounds = displays.reduce(CGRect.null) { $0.union($1) }
        signature = ids.map { id in
            let r = CGDisplayBounds(id)
            return "\(id):\(r.origin.x),\(r.origin.y),\(r.width),\(r.height)"
        }.sorted().joined(separator: ";")
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        if displays.contains(where: { $0.contains(p) }) { return p }
        return displays.map { r in
            CGPoint(x: min(r.maxX - 1, max(r.minX, p.x)), y: min(r.maxY - 1, max(r.minY, p.y)))
        }.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? .zero
    }
    func displayName(_ id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        return screen?.localizedName ?? "Display \(id)"
    }
    func bounds(of id: CGDirectDisplayID) -> CGRect? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return displays[index]
    }
    func calibrationTargets(for id: CGDirectDisplayID) -> [CGPoint] {
        guard let r = bounds(of: id) else { return [] }
        return [Point(0.12, 0.12), Point(0.88, 0.12), Point(0.88, 0.88), Point(0.12, 0.88)].map {
            CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height)
        }
    }
}

final class DesktopControl {
    struct BrowserTabTarget {
        enum Window {
            case chrome(CGWindowID)
            case accessibility(AXUIElement)
        }

        let browser: NSRunningApplication
        let window: Window
        var name: String { browser.localizedName ?? "the browser" }
    }

    private static let chromeBundleID = "com.google.Chrome"
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", chromeBundleID, "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium"
    ]
    private var window: AXUIElement?
    private var selectedWindow: AXUIElement?
    private var windowOrigin: CGPoint = .zero
    private var grabOrigin: CGPoint = .zero
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func moveCursor(_ point: CGPoint) {
        guard isTrusted else { return }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    func scroll(_ pixels: Int32, at point: CGPoint) {
        guard isTrusted, let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                             wheelCount: 1, wheel1: pixels, wheel2: 0, wheel3: 0) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
    func click(at point: CGPoint, selectWindow: Bool = false) -> Bool {
        clearSelection()
        guard isTrusted, !CGEventSource.buttonState(.hidSystemState, button: .left),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
        if selectWindow { selectedWindow = windowAt(point) }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
    func clearSelection() { selectedWindow = nil }

    func minimizeSelection() -> String? {
        let target = selectedWindow
        clearSelection()
        guard isTrusted else { return "Accessibility access is required to minimize a window." }
        guard let target else { return "Point inside an app window and open your palm to select it first." }

        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = focusedWindow(of: pid),
              CFEqual(focused, target) else {
            return "The selected window lost focus. Point at it and open your palm to select it again."
        }
        let result = AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return result == .success ? nil : "This window couldn’t be minimized. Try a regular Finder or browser window."
    }
    func missionControl() {
        guard isTrusted else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                          configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
    func browserTabTarget() -> BrowserTabTarget? {
        guard isTrusted, let front = NSWorkspace.shared.frontmostApplication else { return nil }
        if front.bundleIdentifier == Self.chromeBundleID, let window = visibleChromeWindows(for: front).first {
            return BrowserTabTarget(browser: front, window: .chrome(window))
        }
        if front.processIdentifier == NSRunningApplication.current.processIdentifier {
            let chromeApps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID)
                .filter { !$0.isHidden && !$0.isTerminated }
            guard let chrome = chromeApps.first, chromeApps.count == 1 else { return nil }
            let windows = visibleChromeWindows(for: chrome)
            guard let window = windows.first, windows.count == 1 else { return nil }
            return BrowserTabTarget(browser: chrome, window: .chrome(window))
        }
        guard let id = front.bundleIdentifier, Self.browserBundleIDs.contains(id),
              let window = focusedWindow(of: front.processIdentifier) else { return nil }
        return BrowserTabTarget(browser: front, window: .accessibility(window))
    }

    private func visibleChromeWindows(for chrome: NSRunningApplication) -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let normalLayer = Int(CGWindowLevelForKey(.normalWindow))
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == chrome.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == normalLayer,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }

    @MainActor
    func closeBrowserTab(_ target: BrowserTabTarget) async -> String? {
        guard isTrusted else { return "Accessibility access is required to close a tab." }
        let pid = target.browser.processIdentifier
        let currentPID = NSRunningApplication.current.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == currentPID,
           case .chrome(let windowID) = target.window {
            guard visibleChromeWindows(for: target.browser) == [windowID],
                  target.browser.activate(from: .current, options: []) else {
                return "Click the Chrome tab you want to close, then repeat the gesture."
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.6
            while NSWorkspace.shared.frontmostApplication?.processIdentifier == currentPID,
                  ProcessInfo.processInfo.systemUptime < deadline {
                do { try await Task.sleep(for: .milliseconds(30)) }
                catch { return "Tab close canceled." }
            }
        }

        guard !Task.isCancelled, isTrusted,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return "\(target.name) isn’t in front. Click its tab and try again."
        }
        let sameWindow: Bool
        switch target.window {
        case .chrome(let id):
            sameWindow = visibleChromeWindows(for: target.browser).first == id
        case .accessibility(let window):
            sameWindow = focusedWindow(of: pid).map { CFEqual($0, window) } ?? false
        }
        guard sameWindow else {
            return "The browser window changed. Select a tab and repeat the gesture."
        }
        let key = CGKeyCode(kVK_ANSI_W)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            return "Couldn’t send the close-tab command."
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return nil
    }
    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        guard let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }
    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    private func windowAt(_ point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        if let value = attribute(element, kAXWindowAttribute as CFString), CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        for _ in 0..<12 {
            if (attribute(element, kAXRoleAttribute as CFString) as? String) == kAXWindowRole { return element }
            guard let parent = attribute(element, kAXParentAttribute as CFString), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = parent as! AXUIElement
        }
        return nil
    }
    func grab(at point: CGPoint) -> String? {
        release()
        guard isTrusted else { return "Accessibility access is required for live control." }
        guard let target = windowAt(point) else { return "No movable window at the target. Aim inside an ordinary app window." }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(target, kAXPositionAttribute as CFString, &settable) == .success, settable.boolValue,
              let value = attribute(target, kAXPositionAttribute as CFString), CFGetTypeID(value) == AXValueGetTypeID() else {
            return "This window cannot be moved through Accessibility. Full-screen windows and Mission Control thumbnails aren't supported."
        }
        var origin: CGPoint = .zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &origin) else { return "Could not read this window's position." }
        window = target; windowOrigin = origin; grabOrigin = point
        _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        return nil
    }
    func drag(to point: CGPoint) -> String? {
        guard isTrusted, let window else { return nil }
        var origin = CGPoint(x: windowOrigin.x + point.x - grabOrigin.x, y: windowOrigin.y + point.y - grabOrigin.y)
        guard let value = AXValueCreate(.cgPoint, &origin),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success else {
            release()
            return "The app refused the window move. Release the pinch and try a different window."
        }
        return nil
    }
    func release() { window = nil }
}

private final class TargetBadge: NSView {
    var color = NSColor.systemCyan { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        color.setStroke()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
        ring.lineWidth = 3; ring.stroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: center.x - 22, y: center.y)); cross.line(to: NSPoint(x: center.x + 22, y: center.y))
        cross.move(to: NSPoint(x: center.x, y: center.y - 22)); cross.line(to: NSPoint(x: center.x, y: center.y + 22))
        cross.lineWidth = 2; cross.stroke()
    }
}

final class TargetOverlay {
    private let panel: NSPanel
    private let label: NSTextField
    private let badge = TargetBadge()
    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        label = NSTextField(labelWithString: "")
        label.alignment = .center; label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        badge.frame = NSRect(x: 0, y: 0, width: 260, height: 120)
        panel.contentView?.addSubview(badge)
        label.textColor = .systemCyan; label.frame = NSRect(x: 0, y: 0, width: 260, height: 32)
        panel.contentView?.addSubview(label)
    }
    func show(at point: CGPoint, message: String, live: Bool) {
        // Quartz is top-left based; AppKit is bottom-left based relative to the primary display.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        panel.setFrameOrigin(NSPoint(x: point.x - 130, y: primaryHeight - point.y - 60))
        label.textColor = live ? .systemGreen : .systemCyan
        badge.color = label.textColor ?? .systemCyan
        label.stringValue = message
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}
