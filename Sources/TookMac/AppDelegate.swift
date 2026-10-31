import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TaskStore()
    let preferences = WidgetPreferences()
    let motion = MotionMonitor()
    private var mainWindow: NSWindow!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.tookmac.desktop")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }
        createMainMenu()
        createMainWindow()
        createStatusMenu()
        preferences.windowChanged = { [weak self] in self?.applyPreferences() }
        motion.onDoubleKnock = { [weak self] in self?.togglePlanWindow() }
        applyPreferences()
        if CommandLine.arguments.contains("--verify-window-toggle") {
            showMainWindow()
            let original = mainWindow.windowNumber
            togglePlanWindow()
            precondition(!mainWindow.isVisible)
            togglePlanWindow()
            precondition(mainWindow.isVisible && mainWindow.windowNumber == original)
            hideWindows()
            print("계획 창 열기 → 숨기기 → 같은 창 다시 열기 검증 통과")
            NSApp.terminate(nil)
        } else if CommandLine.arguments.contains("--show-plans") { showMainWindow() }
    }

    private func createMainMenu() {
        let bar = NSMenu()
        let app = NSMenu()
        app.addItem(item("Took Mac 설정…", action: #selector(openSettings), key: ","))
        app.addItem(.separator())
        app.addItem(item("Took Mac 종료", action: #selector(quit), key: "q"))
        let appRoot = NSMenuItem(); appRoot.submenu = app; bar.addItem(appRoot)
        let edit = NSMenu(title: "편집")
        for (title, selector, key) in [("오려두기", "cut:", "x"), ("복사", "copy:", "c"), ("붙여넣기", "paste:", "v"), ("전체 선택", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editRoot = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        editRoot.submenu = edit; bar.addItem(editRoot)
        let window = NSMenu(title: "윈도우")
        window.addItem(item("계획 열기", action: #selector(showMainWindow), key: "0"))
        window.addItem(item("백그라운드로 숨기기", action: #selector(hideWindows), key: "w"))
        let windowRoot = NSMenuItem(title: "윈도우", action: nil, keyEquivalent: "")
        windowRoot.submenu = window; bar.addItem(windowRoot)
        NSApp.mainMenu = bar
    }

    private func createMainWindow() {
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        mainWindow.title = "Took Mac"
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.isOpaque = false
        mainWindow.backgroundColor = .clear
        mainWindow.isReleasedWhenClosed = false
        mainWindow.level = .floating
        mainWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        mainWindow.minSize = NSSize(width: 400, height: 520)
        mainWindow.contentView = FirstClickHostingView(rootView: WidgetView(store: store, preferences: preferences,
            showSettings: { [weak self] in self?.openSettings() }))
        mainWindow.setFrameAutosaveName("TookMainWindow")
        if !mainWindow.setFrameUsingName("TookMainWindow") { mainWindow.center() }
    }

    private func createStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Took Mac")
        statusItem.button?.toolTip = "Took Mac — 계획"
        let menu = NSMenu()
        menu.addItem(item("계획 열기", action: #selector(showMainWindow), key: "o"))
        menu.addItem(item("백그라운드로 숨기기", action: #selector(hideWindows)))
        menu.addItem(item("설정…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Took Mac 종료", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func applyPreferences() {
        let appearance: NSAppearance? = switch preferences.appearance {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        mainWindow.appearance = appearance
        settingsWindow?.appearance = appearance
        motion.configure(enabled: preferences.knockEnabled, threshold: preferences.knockThreshold)
    }

    @objc func showMainWindow() {
        store.refresh()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.orderOut(nil)
    }

    @objc private func togglePlanWindow() {
        if mainWindow.isVisible || settingsWindow?.isVisible == true {
            hideWindows()
            NSApp.deactivate()
        } else { showMainWindow() }
    }

    @objc private func hideWindows() {
        mainWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Took Mac 설정"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.contentView = FirstClickHostingView(rootView: SettingsView(preferences: preferences, store: store, motion: motion))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.orderOut(nil)
    }

    func applicationDidResignActive(_ notification: Notification) {
        if !CommandLine.arguments.contains("--show-plans") { hideWindows() }
    }
    func applicationWillTerminate(_ notification: Notification) { motion.stop() }
    @objc private func quit() { NSApp.terminate(nil) }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "tookmac" }) else { return }
        showMainWindow()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
}

struct SettingsView: View {
    @ObservedObject var preferences: WidgetPreferences
    @ObservedObject var store: TaskStore
    @ObservedObject var motion: MotionMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Took Mac").font(.headline)
            Text("필요할 때 열고, 평소에는 백그라운드에서 기다려요.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("몸체를 두 번 두드려 계획 열고 숨기기", isOn: $preferences.knockEnabled)
            if preferences.knockEnabled {
                Text(motion.status).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("가볍게").font(.caption)
                    Slider(value: $preferences.knockThreshold, in: 0.015...0.20, step: 0.005).accessibilityLabel("두드리는 세기")
                    Text("세게").font(.caption)
                }
                Text("오른쪽 아래 몸체를 톡톡 두드리면 열리고, 다시 톡톡 두드리면 숨겨져요. 입력 직후에는 오작동을 막기 위해 잠시 무시해요.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("두 번 두드림 \(motion.doubleKnockCount)회 인식").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("다시 연결") { motion.stop(); motion.configure(enabled: true, threshold: preferences.knockThreshold) }
                }
                Text("몸체 전체의 진동을 읽으므로 다른 위치의 두드림도 인식할 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("화면 모양", selection: $preferences.appearance) {
                Text("시스템 설정").tag("system")
                Text("밝게").tag("light")
                Text("어둡게").tag("dark")
            }
            Toggle("로그인할 때 자동으로 실행", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Divider()
            Text("바탕화면 우클릭 → 위젯 편집 → Took Mac에서 계획 위젯을 추가할 수 있어요.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("이 맥에 저장되며 원본 Took 및 iCloud와는 연결되지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
            Button("저장 폴더 열기") { store.openDataFolder() }
        }.padding(24).frame(width: 350)
            .alert("설정을 변경하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
    }
}
