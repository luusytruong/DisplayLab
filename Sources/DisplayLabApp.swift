import AppKit

@main
enum DisplayLabApp {
    @MainActor private static var controller: StatusPanelController?

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        controller = StatusPanelController()
        // `--open`: show the panel at launch (handy for testing / scripted screenshots).
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.async { controller?.toggle() }
        }
        app.run()
    }
}
