import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private lazy var notch = NotchController(state: state)
    private lazy var widgets = WidgetController(state: state)
    private var dashboard: DashboardWindowController?
    private var settingsWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no menu bar item — the shelf is the whole presence.
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        state.start()
        notch.onOpenDashboard = { [weak self] in self?.openDashboard() }
        notch.install()

        widgets.onOpenDashboard = { [weak self] in self?.openDashboard() }
        widgets.sync()
        // Toggling a widget anywhere in the UI is just a settings edit; the
        // controller reconciles the on-screen set from that single source.
        settingsWatch = Publishers.Merge(
            state.$settings.map { _ in () },
            state.$isArranging.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.widgets.sync()
            self.dashboard?.setArranging(self.state.isArranging)
        }

        // Documentation aid: render the mascot's animations and exit. See
        // `docs/make-gifs.sh`.
        if let directory = ProcessInfo.processInfo.environment["PERCH_RENDER_MASCOT"] {
            MascotRenderer.render(into: directory)
            NSApp.terminate(nil)
            return
        }

        // Development aid: `PERCH_TAB=projects ./Perch` opens straight to a tab.
        if let name = ProcessInfo.processInfo.environment["PERCH_TAB"],
           let tab = DashboardTab(rawValue: name) {
            dashboard = DashboardWindowController(state: state, initialTab: tab)
            dashboard?.present()
        }
    }

    func openDashboard() {
        if dashboard == nil { dashboard = DashboardWindowController(state: state) }
        dashboard?.setArranging(state.isArranging)
        dashboard?.present()
    }

    /// An accessory app still shows a menu bar while its window is focused, and it
    /// is the only place ⌘Q and the text-editing shortcuts can live.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Open Dashboard",
            action: #selector(openDashboardAction), keyEquivalent: "d"
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func openDashboardAction() { openDashboard() }
}
