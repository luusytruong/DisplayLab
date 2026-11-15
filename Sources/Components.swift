import SwiftUI

/// Full-width menu row (like native menus / Control Center): rounded highlight on hover, deeper on press.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverBody(configuration: configuration) }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.13 : hovering ? 0.07 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Capsule chip: accent fill when selected, soft fill otherwise; brightens on hover, shrinks on press.
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, selected: selected)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    Capsule().fill(selected
                        ? AnyShapeStyle(Color.accentColor.opacity(hovering ? 0.88 : 1))
                        : AnyShapeStyle(Color.primary.opacity(hovering ? 0.12 : 0.06))))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .onHover { hovering = $0 }
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Control Center–style slider over discrete steps: thick capsule track, accent fill, white knob.
struct CapsuleSlider: View {
    @Binding var index: Double
    let count: Int
    var onEditingChanged: (Bool) -> Void

    @State private var hovering = false
    @State private var dragging = false
    private let height: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - height, 1)
            let fraction = count > 1 ? index / Double(count - 1) : 0
            let fill = height + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(hovering || dragging ? 0.12 : 0.08))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: fill)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(3)
                    .frame(width: height, height: height)
                    .scaleEffect(dragging ? 1.08 : 1)
                    .offset(x: fill - height)
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        let f = min(max((g.location.x - height / 2) / travel, 0), 1)
                        index = (f * Double(count - 1)).rounded()
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    })
            .animation(dragging ? .interactiveSpring(duration: 0.12) : .snappy(duration: 0.25), value: index)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(duration: 0.2), value: dragging)
        }
        .frame(height: height)
    }
}
