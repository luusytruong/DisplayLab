import AppKit
import CoreGraphics

struct Mode: Identifiable, Equatable {
    let width: Int
    let height: Int
    let refresh: Double
    let hiDPI: Bool
    let cg: CGDisplayMode
    var id: String { "\(width)x\(height)" }
    static func == (a: Mode, b: Mode) -> Bool { a.id == b.id }
}

struct Screen: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
}

@MainActor
final class DisplayStore: ObservableObject {
    @Published private(set) var screens: [Screen] = []
    @Published var selectedID: CGDirectDisplayID = CGMainDisplayID() { didSet { reload() } }
    /// Modes matching the panel's aspect ratio, one per size, sorted by width. Built-in: HiDPI only.
    /// External: HiDPI where available, plain 1x otherwise, and always 1x at native size.
    @Published private(set) var modes: [Mode] = []
    @Published private(set) var current: Mode?
    @Published private(set) var currentSize = (width: 0, height: 0, refresh: 0.0)
    @Published private(set) var native = (width: 0, height: 0)
    @Published private(set) var overrideCount: Int?
    @Published var message: String?

    /// Called right before a resolution switch, and after it with whether it succeeded.
    var onModeWillChange: (() -> Void)?
    var onModeDidChange: ((Bool) -> Void)?

    private static let nativeFlag: UInt32 = 0x0200_0000

    init() {
        reloadScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadScreens() }
        }
    }

    var selectedScreen: Screen? { screens.first { $0.id == selectedID } }

    var isBuiltin: Bool { selectedScreen?.isBuiltin ?? true }

    /// The "100% text size" reference: built-in = Retina 2x default (native / 2),
    /// external = native resolution at 1x (macOS's default for most monitors).
    var referenceWidth: Int { max(isBuiltin ? native.width / 2 : native.width, 1) }

    /// Text-size ratios for the quick-pick chips, relative to `referenceWidth`.
    /// Built-in on a 15" Air: 1710 (macOS's own default) / 1805 / 1901 / 2016 / 2102.
    var presetRatios: [Double] {
        isBuiltin ? [1710.0, 1805, 1901, 2016, 2102].map { 1440 / $0 } : [2.0, 1.5, 1.33, 1.15, 1.0]
    }

    /// Physical panel pixels per logical point. 2.0 = Retina 2x (pixel-perfect, sharpest); lower means
    /// macOS downsamples a larger canvas, so every glyph is drawn with fewer real pixels.
    func pixelsPerPoint(width: Int) -> Double { Double(native.width) / Double(max(width, 1)) }

    func reloadScreens() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        screens = ids.map { Screen(id: $0, name: Self.name(for: $0), isBuiltin: CGDisplayIsBuiltin($0) != 0) }
        if !screens.contains(where: { $0.id == selectedID }) {
            selectedID = screens.first(where: \.isBuiltin)?.id ?? CGMainDisplayID()
        } else {
            reload()
        }
    }

    func reload() {
        let id = selectedID
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []

        let nativeMode = all.first { $0.ioFlags & Self.nativeFlag != 0 }
            ?? all.filter { $0.pixelWidth == $0.width }.max { $0.width < $1.width }
        native = (nativeMode?.pixelWidth ?? 0, nativeMode?.pixelHeight ?? 0)

        let cur = CGDisplayCopyDisplayMode(id)
        currentSize = (cur?.width ?? 0, cur?.height ?? 0, cur?.refreshRate ?? 0)

        let aspect = native.height > 0 ? Double(native.width) / Double(native.height) : 0
        let builtin = CGDisplayIsBuiltin(id) != 0
        let hz = currentSize.refresh
        // Higher wins: preferred kind for this size (HiDPI, except 1x at external native), then current Hz, then max Hz.
        func score(_ m: CGDisplayMode) -> Double {
            let hidpi = m.pixelWidth == m.width * 2
            let atNative = m.width == native.width && m.height == native.height
            let preferred = builtin || !atNative ? hidpi : !hidpi
            return (preferred ? 1_000_000 : 0) + (m.refreshRate == hz ? 1000 : 0) + m.refreshRate
        }
        // Notched built-ins pair every full-panel size with a 16:10 "below the notch" twin; sizes
        // without one (e.g. 1642x1062 on a 15" Air) don't fill the panel, so drop them.
        let notchTwins = Set(all.filter {
            $0.pixelWidth == $0.width * 2 && abs(Double($0.width) / Double($0.height) - 1.6) < 0.01
        }.map(\.width))
        let requireTwin = builtin && abs(aspect - 1.6) > 0.01 && !notchTwins.isEmpty

        var best: [String: CGDisplayMode] = [:]
        for m in all where m.isUsableForDesktopGUI() {
            let hidpi = m.pixelWidth == m.width * 2
            guard hidpi || (!builtin && m.pixelWidth == m.width) else { continue }
            if requireTwin, !notchTwins.contains(m.width) { continue }
            if aspect > 0, abs(Double(m.width) / Double(m.height) - aspect) / aspect > 0.01 { continue }
            let key = "\(m.width)x\(m.height)"
            if let old = best[key], score(m) <= score(old) { continue }
            best[key] = m
        }
        modes = best.values
            .map { Mode(width: $0.width, height: $0.height, refresh: $0.refreshRate,
                        hiDPI: $0.pixelWidth == $0.width * 2, cg: $0) }
            .sorted { $0.width < $1.width }
        current = modes.first { $0.width == currentSize.width && $0.height == currentSize.height }
        overrideCount = OverrideInstaller.installedCount(
            vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
    }

    func apply(_ mode: Mode) {
        guard mode != current else { return }
        onModeWillChange?()
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            message = L("Couldn't open the display configuration.")
            onModeDidChange?(false)
            return
        }
        CGConfigureDisplayWithDisplayMode(config, selectedID, mode.cg, nil)
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result != .success {
            CGCancelDisplayConfiguration(config)
            message = L("Couldn't change the resolution (code %@).", String(result.rawValue))
        } else {
            message = nil
        }
        reload()
        onModeDidChange?(result == .success)
    }

    /// Picks the mode closest to `ratio` × reference text size (1.0 = sharpest 2x).
    func mode(forTextSize ratio: Double) -> Mode? {
        let target = Double(referenceWidth) / ratio
        return modes.min { abs(Double($0.width) - target) < abs(Double($1.width) - target) }
    }

    func installExtendedModes() {
        let id = selectedID
        do {
            let added = try OverrideInstaller.install(
                vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                nativeWidth: native.width, nativeHeight: native.height)
            if added == 0 {
                message = L("Extended modes are already complete; nothing to write.")
            } else {
                message = isBuiltin
                    ? L("Added %@ modes. Log out or restart so macOS loads them.", String(added))
                    : L("Added %@ modes. Reconnect the display (or log out) so macOS loads them.", String(added))
            }
        } catch {
            message = error.localizedDescription
        }
        reload()
    }

    private static func name(for id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? L("Display %@", String(id))
    }
}
