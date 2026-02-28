import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Config

let bundleID = "com.sixth.pandora.uitest"
let appName = "Sixth-UITest.app"
let outputDir = "/tmp/sixth-ui-test"

// MARK: - Helpers

func log(_ msg: String) {
    let ts = DateFormatter()
    ts.dateFormat = "HH:mm:ss.SSS"
    print("[\(ts.string(from: Date()))] \(msg)")
}

func getWindows(forPID pid: pid_t) -> [[String: Any]] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return [] }
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
}

struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect

    var description: String {
        "(\(Int(frame.origin.x)), \(Int(frame.origin.y)), \(Int(frame.size.width)), \(Int(frame.size.height))) [id: \(id)]"
    }
}

func windowInfo(from dict: [String: Any]) -> WindowInfo? {
    guard let id = dict[kCGWindowNumber as String] as? CGWindowID,
          let bounds = dict[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? CGFloat,
          let y = bounds["Y"] as? CGFloat,
          let w = bounds["Width"] as? CGFloat,
          let h = bounds["Height"] as? CGFloat else { return nil }
    return WindowInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h))
}

/// Find all menubar-height windows for this pid (status items live here)
func findStatusItemWindows(pid: pid_t) -> [WindowInfo] {
    let windows = getWindows(forPID: pid)
    return windows.compactMap { windowInfo(from: $0) }
        .filter { $0.frame.origin.y <= 5 && $0.frame.size.height <= 30 }
}

/// The icon item is always present and narrow (~27px).
func findIconWindow(pid: pid_t) -> WindowInfo? {
    let items = findStatusItemWindows(pid: pid)
    // Icon is the narrowest status item
    return items.min(by: { $0.frame.size.width < $1.frame.size.width })
}

/// The scroller item is wide (>50px) and only exists when scrolling is enabled.
func findScrollerWindow(pid: pid_t) -> WindowInfo? {
    let items = findStatusItemWindows(pid: pid)
    return items.first(where: { $0.frame.size.width > 50 })
}

func findPopoverWindow(pid: pid_t, excludingIDs: Set<CGWindowID>) -> WindowInfo? {
    let windows = getWindows(forPID: pid)
    for w in windows {
        guard let info = windowInfo(from: w) else { continue }
        if !excludingIDs.contains(info.id)
            && info.frame.size.height > 50
            && info.frame.origin.y > 5 {
            return info
        }
    }
    return nil
}

func click(at point: CGPoint) {
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: point, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: point, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(50_000)
    up?.post(tap: .cghidEventTap)
}

func screenshot(windowID: CGWindowID, to path: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-l", "\(windowID)", "-x", path]
    try? proc.run()
    proc.waitUntilExit()
    log("Screenshot: \(path)")
}

func wait(_ seconds: Double) {
    usleep(UInt32(seconds * 1_000_000))
}

// MARK: - AXUIElement Helpers

func findElement(in element: AXUIElement, role: String, titleOrDesc: String) -> AXUIElement? {
    var roleVal: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
    let currentRole = roleVal as? String

    if currentRole == role {
        var titleVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal)
        if let t = titleVal as? String, t.contains(titleOrDesc) { return element }

        var descVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descVal)
        if let d = descVal as? String, d.contains(titleOrDesc) { return element }
    }

    var children: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
    for child in (children as? [AXUIElement]) ?? [] {
        if let found = findElement(in: child, role: role, titleOrDesc: titleOrDesc) {
            return found
        }
    }
    return nil
}

func findElementByTitle(in element: AXUIElement, title: String) -> AXUIElement? {
    var titleVal: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal)
    if let t = titleVal as? String, t.contains(title) { return element }

    var children: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
    for child in (children as? [AXUIElement]) ?? [] {
        if let found = findElementByTitle(in: child, title: title) {
            return found
        }
    }
    return nil
}

func axPress(_ element: AXUIElement) {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

func axValue(_ element: AXUIElement) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    return value
}

func dumpTree(_ element: AXUIElement, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    var title: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    var desc: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    let r = (role as? String) ?? "?"
    let t = (title as? String) ?? ""
    let d = (desc as? String) ?? ""
    let v = value.map { "\($0)" } ?? ""
    print("\(pad)\(r) title=\"\(t)\" desc=\"\(d)\" value=\"\(v)\"")
    var children: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
    for child in (children as? [AXUIElement]) ?? [] {
        dumpTree(child, indent: indent + 1)
    }
}

// MARK: - Test State

var testsPassed = 0
var testsFailed = 0
var popoverFrames: [(String, CGRect)] = []

func check(_ label: String, _ condition: Bool, detail: String = "") {
    if condition {
        testsPassed += 1
        print("  \u{2713} \(label)")
    } else {
        testsFailed += 1
        print("  \u{2717} \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

func isCheckboxOn(_ cb: AXUIElement) -> Bool {
    if let v = axValue(cb) as? Int { return v == 1 }
    if let v = axValue(cb) as? NSNumber { return v.intValue == 1 }
    return false
}

// MARK: - Main

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("=== Sixth UI Anchor Test ===\n")

// Step 0: Find or launch the UI test app
let ws = NSWorkspace.shared
let runningApps = ws.runningApplications.filter { $0.bundleIdentifier == bundleID }
let app: NSRunningApplication
if let existing = runningApps.first {
    app = existing
    log("Found \(appName) (PID \(app.processIdentifier))")
} else {
    let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(appName)
    guard FileManager.default.fileExists(atPath: appURL.path) else {
        print("ERROR: \(appName) not found. Build first with ./build.sh")
        exit(1)
    }
    let config = NSWorkspace.OpenConfiguration()
    var launched: NSRunningApplication?
    let sem = DispatchSemaphore(value: 0)
    ws.openApplication(at: appURL, configuration: config) { result, error in
        launched = result
        if let error = error {
            print("ERROR: Failed to launch \(appName): \(error)")
        }
        sem.signal()
    }
    sem.wait()
    guard let l = launched else {
        print("ERROR: Could not launch \(appName)")
        exit(1)
    }
    app = l
    log("Launched \(appName) (PID \(app.processIdentifier))")
    wait(3)
}
let pid = app.processIdentifier
let axApp = AXUIElementCreateApplication(pid)

// Helpers that capture pid
func clickIconItem() {
    guard let win = findIconWindow(pid: pid) else { return }
    click(at: CGPoint(x: win.frame.midX, y: win.frame.midY))
}

func scrollerPresent() -> Bool {
    return findScrollerWindow(pid: pid) != nil
}

func iconWidth() -> Int {
    guard let win = findIconWindow(pid: pid) else { return -1 }
    return Int(win.frame.size.width)
}

func closePopover() {
    // Click well away from the status item to dismiss
    click(at: CGPoint(x: 10, y: 400))
    wait(1.0)
}

func navigateToSettings() {
    if let btn = findElement(in: axApp, role: "AXButton", titleOrDesc: "Settings") {
        axPress(btn)
        wait(0.3)
        if let mi = findElementByTitle(in: axApp, title: "Settings") {
            axPress(mi)
            wait(0.5)
        }
    }
}

let initialWindowIDs = Set(getWindows(forPID: pid).compactMap { windowInfo(from: $0)?.id })

let iw = iconWidth()
log("Icon item width: \(iw)px")
log("Scroller present: \(scrollerPresent())")

// ── Part 1: Popover position stability ──────────────────────────
print("\nPart 1: Popover position stability during toggles")

clickIconItem()
wait(0.8)

guard let popover1 = findPopoverWindow(pid: pid, excludingIDs: initialWindowIDs) else {
    print("ERROR: Popover did not appear")
    exit(1)
}
log("Popover opened: \(popover1.description)")
screenshot(windowID: popover1.id, to: "\(outputDir)/01-popover-open.png")
popoverFrames.append(("initial", popover1.frame))

navigateToSettings()

if let p = findPopoverWindow(pid: pid, excludingIDs: initialWindowIDs) {
    screenshot(windowID: p.id, to: "\(outputDir)/02-settings.png")
}

// Read checkbox state before toggling
guard let checkbox = findElement(in: axApp, role: "AXCheckBox", titleOrDesc: "Scrolling title") else {
    print("ERROR: Could not find scrolling title checkbox")
    dumpTree(axApp)
    exit(1)
}

let startedOn = isCheckboxOn(checkbox)
log("Scrolling title initially: \(startedOn ? "ON" : "OFF")")

// Toggle 3 times and record popover position each time
for i in 1...3 {
    let wasOn = isCheckboxOn(checkbox)
    axPress(checkbox)
    wait(1.0)
    let nowOn = !wasOn
    let label = "toggle\(i)-scroll-\(nowOn ? "on" : "off")"
    if let p = findPopoverWindow(pid: pid, excludingIDs: initialWindowIDs) {
        popoverFrames.append((label, p.frame))
        screenshot(windowID: p.id, to: "\(outputDir)/0\(2+i)-\(label).png")
    }
}

let xPositions = popoverFrames.map { Int($0.1.origin.x) }
let drift = (xPositions.max() ?? 0) - (xPositions.min() ?? 0)
print("  Popover X positions: \(xPositions)")
check("popover stable during toggles (drift \(drift)px)", drift <= 5)

// ── Part 2: Icon stays fixed, scroller appears/disappears ─────────
print("\nPart 2: Icon item stable, scroller appears/disappears on toggle")

// Determine current checkbox state (after 3 toggles)
let scrollAfterPart1 = isCheckboxOn(checkbox)
log("Scroll state after Part 1: \(scrollAfterPart1 ? "ON" : "OFF")")

// Close popover and check icon stays narrow, scroller matches state
closePopover()
let popoverGone = findPopoverWindow(pid: pid, excludingIDs: initialWindowIDs) == nil
check("popover closed", popoverGone)

let iw1 = iconWidth()
log("Icon width after close: \(iw1)px")
check("icon always narrow", iw1 < 50, detail: "got \(iw1)px, expected <50px")

let scroller1 = scrollerPresent()
log("Scroller present (scroll \(scrollAfterPart1 ? "ON" : "OFF")): \(scroller1)")
if scrollAfterPart1 {
    check("scroll ON: scroller present after close", scroller1)
} else {
    check("scroll OFF: scroller absent after close", !scroller1)
}

// Toggle to the opposite state, close, verify scroller changed
clickIconItem()
wait(0.8)
navigateToSettings()

guard let cb2 = findElement(in: axApp, role: "AXCheckBox", titleOrDesc: "Scrolling title") else {
    print("ERROR: Could not find checkbox on reopen")
    exit(1)
}
let before2 = isCheckboxOn(cb2)
log("Toggling scroll from \(before2 ? "ON" : "OFF") to \(before2 ? "OFF" : "ON")...")
axPress(cb2)
wait(0.5)
let after2 = !before2

closePopover()

let iw2 = iconWidth()
log("Icon width after close: \(iw2)px")
check("icon still narrow after toggle", iw2 < 50, detail: "got \(iw2)px, expected <50px")

let scroller2 = scrollerPresent()
log("Scroller present (scroll \(after2 ? "ON" : "OFF")): \(scroller2)")
if after2 {
    check("scroll ON: scroller present after close", scroller2)
} else {
    check("scroll OFF: scroller absent after close", !scroller2)
}

// Toggle back, close, verify again
clickIconItem()
wait(0.8)
navigateToSettings()

guard let cb3 = findElement(in: axApp, role: "AXCheckBox", titleOrDesc: "Scrolling title") else {
    print("ERROR: Could not find checkbox on reopen")
    exit(1)
}
let before3 = isCheckboxOn(cb3)
log("Toggling scroll from \(before3 ? "ON" : "OFF") to \(before3 ? "OFF" : "ON")...")
axPress(cb3)
wait(0.5)
let after3 = !before3

closePopover()

let iw3 = iconWidth()
log("Icon width after close: \(iw3)px")
check("icon still narrow after second toggle", iw3 < 50, detail: "got \(iw3)px, expected <50px")

let scroller3 = scrollerPresent()
log("Scroller present (scroll \(after3 ? "ON" : "OFF")): \(scroller3)")
if after3 {
    check("scroll ON: scroller present after close", scroller3)
} else {
    check("scroll OFF: scroller absent after close", !scroller3)
}

// ── Summary ──────────────────────────────────────────────────────
print("\n=== Summary ===")
print("Icon widths: \(iw1)px, \(iw2)px, \(iw3)px (should all be <50)")
print("Scroller: close1=\(scroller1) (scroll \(scrollAfterPart1 ? "ON" : "OFF")), close2=\(scroller2) (scroll \(after2 ? "ON" : "OFF")), close3=\(scroller3) (scroll \(after3 ? "ON" : "OFF"))")
print("\(testsPassed) passed, \(testsFailed) failed")

if testsFailed > 0 {
    print("\nFAIL")
    exit(1)
} else {
    print("\nPASS")
}
