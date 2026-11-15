import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that can take key focus (so ⌘Q / Esc work) without activating the app.
final class StatusPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Menu bar icon + dropdown panel. Unlike SwiftUI's MenuBarExtra, this closes when focus leaves
/// or the Space changes, and re-anchors under the icon whenever the screen or menu bar moves.
@MainActor
final class StatusPanelController: NSObject {
    static let cornerRadius: CGFloat = 20

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = StatusPanel()
    private let store = DisplayStore()
    private var contentSize = CGSize(width: 300, height: 400)
    private var lastClosed = Date.distantPast
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var hotKey: HotKey?
    private var iconClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var menuTracking = false
    /// True while the panel is hidden for a resolution switch; it reappears once the new
    /// screen geometry is reported (re-anchoring on menu bar moves stays as the fallback).
    private var switching = false

    /// Shown in the panel header; keep in sync with the registration below.
    static let hotKeyHint = "⌃⌥⌘D"

    override init() {
        super.init()

        // Remembers where the user ⌘-drags the icon (e.g. out from under the notch) across launches.
        statusItem.autosaveName = "DisplayLab"
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
        }

        // Handle clicks on the icon ourselves, on mouse-down, and swallow them: if NSStatusBarButton
        // ran its own click tracking it would clear the highlight on mouse-up, so the icon would
        // flicker instead of staying lit while the panel is open (same approach as FluidMenuBarExtra).
        // ⌘-clicks pass through so the icon can still be ⌘-dragged to another spot.
        iconClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let onIcon = event.window != nil && !event.modifierFlags.contains(.command)
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard onIcon, let self, windowNumber == self.statusItem.button?.window?.windowNumber else { return false }
                self.toggle()
                return true
            }
            return handled ? nil : event
        }
        // A click in another app (including another menu bar item) closes the panel, which, being
        // non-activating, doesn't always lose key status on its own.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let root = PanelRoot(store: store) { [weak self] size in self?.resize(to: size) }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
        panel.onCancel = { [weak self] in self?.close() }
        // Lay the SwiftUI content out now so the first click doesn't pay for it.
        hosting.layoutSubtreeIfNeeded()

        store.onModeWillChange = { [weak self] in self?.beginSwitch() }
        store.onModeDidChange = { [weak self] success in self?.endSwitch(success: success) }

        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, panel) { $0.close() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { $0.close() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.switching ? $0.show() : $0.reposition()
        }
        observe(NotificationCenter.default, NSWindow.didMoveNotification, statusItem.button?.window) { $0.reposition() }

        // Opens the panel even when the icon is pushed off the menu bar (notch / too many icons).
        hotKey = HotKey(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey | cmdKey, id: 1) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if panel.isVisible {
            close()
            return
        }
        // A click on the icon first resigns the panel's key status (closing it); don't reopen.
        guard Date().timeIntervalSince(lastClosed) > 0.25 else { return }
        store.reload()
        show()
    }

    /// Shown instantly (no fade), like a native menu.
    private func show() {
        switching = false
        reposition()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        setMenuTracking(true)
    }

    /// While "menu tracking" is on, macOS keeps an auto-hidden menu bar (full-screen apps) visible,
    /// exactly as it does for a real menu, so the panel doesn't lose its icon above it.
    private func setMenuTracking(_ on: Bool) {
        guard on != menuTracking else { return }
        menuTracking = on
        let name = on ? "com.apple.HIToolbox.beginMenuTrackingNotification"
                      : "com.apple.HIToolbox.endMenuTrackingNotification"
        DistributedNotificationCenter.default().post(name: Notification.Name(name), object: nil)
    }

    private func beginSwitch() {
        guard panel.isVisible else { return }
        switching = true
        panel.orderOut(nil)
    }

    private func endSwitch(success: Bool) {
        // On success, show() runs when macOS posts the new screen parameters.
        // On failure nothing will be posted, so bring the panel (with the error) back now.
        if switching, !success { show() }
    }

    private func close() {
        guard !switching, panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = Date()
        statusItem.button?.highlight(false)
        setMenuTracking(false)
    }

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        reposition()
    }

    /// Pins the panel's top-left under the status icon, kept inside the screen's visible area.
    private func reposition() {
        guard let anchor = statusItem.button?.window?.frame else { return }
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        // Icon hidden (behind the notch, overflowed, or menu bar auto-hidden): sit top-right like Control Center.
        let iconVisible = statusItem.button?.window?.occlusionState.contains(.visible) == true
        var x = iconVisible ? anchor.minX : .greatestFiniteMagnitude
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - contentSize.width - 8)
        }
        // When the menu bar auto-hides (full-screen apps, "hide menu bar"), the icon's window slides
        // above the screen; keep the panel where the menu bar's bottom edge would be instead.
        var top = anchor.minY
        if let screen {
            top = min(top, screen.frame.maxY - NSStatusBar.system.thickness)
        }
        let frame = NSRect(x: x, y: top - 6 - contentSize.height,
                           width: contentSize.width, height: contentSize.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ object: Any? = nil,
                         _ handler: @escaping (StatusPanelController) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    /// Template (monochrome) version of the app icon: a monitor with the slider inside.
    private static func menuBarIcon() -> NSImage {
        // Drawn on an 18×15 grid, scaled ×1.2 to 18pt tall (the height of typical menu bar icons, e.g. Docker).
        let scale: CGFloat = 1.2
        let image = NSImage(size: NSSize(width: 18 * scale, height: 15 * scale), flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            NSColor.black.set()
            // Bezel outline (~1.6pt stroke after scaling)
            let bezel = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 4.25, width: 16.5, height: 10), xRadius: 2.5, yRadius: 2.5)
            bezel.lineWidth = 1.35
            bezel.stroke()
            // Stand
            NSBezierPath(rect: NSRect(x: 8, y: 1.5, width: 2, height: 2.75)).fill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 0.5, width: 8, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            // Slider: filled part, faint rest of the track, knob
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 8.5, width: 6.5, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSColor.black.withAlphaComponent(0.35).set()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 8.5, width: 4.5, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSColor.black.set()
            NSBezierPath(ovalIn: NSRect(x: 8.25, y: 7.25, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DisplayLab"
        return image
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Lays MenuView out at its natural size and reports that size so the panel can fit it.
private struct PanelRoot: View {
    @ObservedObject var store: DisplayStore
    let onSize: (CGSize) -> Void

    var body: some View {
        MenuView(store: store)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(
                RoundedRectangle(cornerRadius: StatusPanelController.cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}
