import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var store: DisplayStore
    @State private var slider: Double = 0
    @State private var dragging = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.screens.count > 1 {
                Picker("", selection: $store.selectedID) {
                    ForEach(store.screens) { Text($0.isBuiltin ? L("Built-in") : $0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if store.modes.isEmpty {
                Text(L("Couldn't read this display's modes. Try “Add extended modes”."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                resolutionCard
                presets
            }
            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            footer
        }
        .padding(12)
        .frame(width: 300)
        // No keyboard focus ring on the first chip when the panel opens (it reads as "selected").
        .focusEffectDisabled()
        .onAppear {
            store.reload()
            syncSlider(animated: false)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: store.current) { if !dragging { syncSlider() } }
        .onChange(of: store.modes) { if !dragging { syncSlider() } }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            // The app icon (white tile, monitor with slider); its artwork has macOS's standard
            // transparent margin, so the frame is a bit larger than the visible tile.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .padding(-4)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.selectedScreen.map { $0.isBuiltin ? L("Built-in Display") : $0.name } ?? L("Display"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(L("Native %@ × %@ · %@ Hz", String(store.native.width), String(store.native.height),
                       String(Int(store.currentSize.refresh.rounded()))))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(StatusPanelController.hotKeyHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .help(L("Shortcut to open this panel, even when the menu bar icon is hidden"))
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var resolutionCard: some View {
        let shown = dragging ? modeAtSlider : store.current
        let width = shown?.width ?? store.currentSize.width
        let height = shown?.height ?? store.currentSize.height
        let density = store.pixelsPerPoint(width: width)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("\(String(width)) × \(String(height))")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: width)
                Spacer()
                if let badge = badge(for: shown, width: width) {
                    Label(badge.title, systemImage: badge.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(badge.color.opacity(0.16)))
                        .foregroundStyle(badge.color)
                }
            }
            Text(dragging ? L("Release to apply")
                 : L("Sharpness %@%% · %@ px per point", String(Int((density / 2 * 100).rounded())),
                     String(format: "%.2f", density)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .help(L("Real display pixels per UI point. 2.00 = Retina 2x, the sharpest; the lower it is, the fewer pixels each letter gets and the softer text looks."))

            HStack(spacing: 8) {
                sizeGlyph(size: 16).help(L("Larger text"))
                CapsuleSlider(index: $slider, count: store.modes.count) { editing in
                    dragging = editing
                    if !editing, let mode = modeAtSlider { store.apply(mode) }
                }
                .disabled(store.modes.count < 2)
                sizeGlyph(size: 11).help(L("More space"))
            }
            .padding(.top, 14)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))))
    }

    private var presets: some View {
        let options = store.presetRatios.compactMap(store.mode(forTextSize:))
            .reduce(into: [Mode]()) { if !$0.contains($1) { $0.append($1) } }

        return HStack(spacing: 6) {
            ForEach(options) { mode in
                Button(String(mode.width)) { store.apply(mode) }
                    .buttonStyle(ChipButtonStyle(selected: mode == store.current))
                    .help("\(String(mode.width)) × \(String(mode.height))")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Divider().padding(.horizontal, 6).padding(.bottom, 4)

            Button { launchAtLogin.toggle() } label: {
                rowLabel(L("Open at login"), icon: "power") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }

            Button { store.installExtendedModes() } label: {
                rowLabel(L("Add extended modes"), icon: "square.stack.3d.up") {
                    Text(store.overrideCount.map(String.init) ?? L("None"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .help(L("Adds 16-point HiDPI steps to macOS's display override file (asks for an admin password if the file doesn't exist yet)"))

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            } label: {
                rowLabel(L("Display Settings…"), icon: "gearshape") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Button { NSApp.terminate(nil) } label: {
                rowLabel(L("Quit"), icon: "xmark.circle") {
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: Helpers

    private func rowLabel<Trailing: View>(_ title: String, icon: String,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func badge(for mode: Mode?, width: Int) -> (title: String, icon: String, color: Color)? {
        if width * 2 == store.native.width, mode?.hiDPI ?? true {
            return (L("Sharpest"), "sparkles", .green)
        }
        guard let mode, !mode.hiDPI else { return nil }
        return mode.width == store.native.width
            ? (L("Native"), "checkmark.circle", .secondary)
            : (L("Not HiDPI"), "exclamationmark.triangle", .orange)
    }

    /// Big "A" (larger text) / small "A" (more space) flanking the slider, in equal-width slots.
    private func sizeGlyph(size: CGFloat) -> some View {
        Text(verbatim: "A")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }

    private var modeAtSlider: Mode? {
        let i = Int(slider.rounded())
        return store.modes.indices.contains(i) ? store.modes[i] : nil
    }

    private func syncSlider(animated: Bool = true) {
        guard let current = store.current, let i = store.modes.firstIndex(of: current) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { slider = Double(i) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            try on ? service.register() : service.unregister()
        } catch {
            store.message = L("Couldn't turn on Open at login: %@", error.localizedDescription)
            launchAtLogin = service.status == .enabled
        }
    }
}
