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
                    ForEach(store.screens) { Text($0.isBuiltin ? "Tích hợp" : $0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if store.modes.isEmpty {
                Text("Không đọc được mode của màn hình này. Thử bấm “Bổ sung mode mở rộng”.")
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
            Image(systemName: store.selectedScreen?.isBuiltin == false ? "display" : "laptopcomputer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 0) {
                Text(store.selectedScreen.map { $0.isBuiltin ? "Màn hình tích hợp" : $0.name } ?? "Màn hình")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Gốc \(String(store.native.width)) × \(String(store.native.height)) · \(String(Int(store.currentSize.refresh.rounded()))) Hz")
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
                .help("Phím tắt mở bảng này, kể cả khi icon bị ẩn trên menu bar")
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
            Text(dragging ? "Thả tay để áp dụng"
                 : String(format: "Độ nét %d%% · %.2f px mỗi điểm", Int((density / 2 * 100).rounded()), density))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .help("Số điểm ảnh thật của màn hình cho mỗi điểm giao diện. 2.00 = Retina 2x, nét nhất; càng thấp thì mỗi chữ càng ít điểm ảnh nên càng kém nét.")

            HStack(spacing: 8) {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Chữ to")
                CapsuleSlider(index: $slider, count: store.modes.count) { editing in
                    dragging = editing
                    if !editing, let mode = modeAtSlider { store.apply(mode) }
                }
                .disabled(store.modes.count < 2)
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Nhiều không gian")
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
                rowLabel("Mở cùng macOS", icon: "power") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }

            Button { store.installExtendedModes() } label: {
                rowLabel("Bổ sung mode mở rộng", icon: "square.stack.3d.up") {
                    Text(store.overrideCount.map(String.init) ?? "Chưa có")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .help("Ghi thêm bậc 16 point vào override plist của macOS (cần quyền admin nếu file chưa có)")

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            } label: {
                rowLabel("Cài đặt Màn hình…", icon: "gearshape") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Button { NSApp.terminate(nil) } label: {
                rowLabel("Thoát", icon: "xmark.circle") {
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
            return ("Nét nhất", "sparkles", .green)
        }
        guard let mode, !mode.hiDPI else { return nil }
        return mode.width == store.native.width
            ? ("Gốc", "checkmark.circle", .secondary)
            : ("Không HiDPI", "exclamationmark.triangle", .orange)
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
            store.message = "Không bật được mở cùng macOS: \(error.localizedDescription)"
            launchAtLogin = service.status == .enabled
        }
    }
}
