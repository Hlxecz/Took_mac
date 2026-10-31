import AppKit
import SwiftUI
import ServiceManagement
import TookCore

@MainActor
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = TaskStore()
    let preferences = WidgetPreferences()
    private var panel: DesktopPanel!
    private var mainWindow: NSWindow!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var visibilityItem: NSMenuItem!
    private var pinItem: NSMenuItem!
    private var cornerTimer: Timer?
    private var cornerTrigger = ScreenCornerTrigger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createMainMenu()
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.tookmac.desktop")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !otherInstances.isEmpty { NSApp.terminate(nil); return }
        createMainWindow()
        createPanel()
        createMenu()
        preferences.windowChanged = { [weak self] in self?.applyPreferences() }
        applyPreferences()
        showMainWindow()
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
        window.addItem(item("할 일 앱 열기", action: #selector(showMainWindow), key: "0"))
        window.addItem(item("바탕화면 위젯 보기", action: #selector(showWidget), key: "1"))
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
        mainWindow.minSize = NSSize(width: 400, height: 520)
        mainWindow.contentView = NSHostingView(rootView: WidgetView(store: store, preferences: preferences,
            showSettings: { [weak self] in self?.openSettings() }, isDesktop: false))
        mainWindow.setFrameAutosaveName("TookMainWindow")
        if !mainWindow.setFrameUsingName("TookMainWindow") { mainWindow.center() }
    }

    @objc func showMainWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createPanel() {
        panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
                             styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Took Mac"
        panel.identifier = NSUserInterfaceItemIdentifier("TookDesktopWidget")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 350, height: 430)
        panel.maxSize = NSSize(width: 500, height: 900)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WidgetView(store: store, preferences: preferences, showSettings: { [weak self] in self?.openSettings() }, showApp: { [weak self] in self?.showMainWindow() }))
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let defaultFrame = NSRect(x: visible.maxX - 394, y: visible.maxY - 534, width: 360, height: 500)
        if let value = UserDefaults.standard.string(forKey: "widgetFrame") {
            var saved = NSRectFromString(value)
            saved.size.width = min(max(saved.width, 350), 500)
            saved.size.height = min(max(saved.height, 430), 900)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersection(saved).width >= 100 && $0.visibleFrame.intersection(saved).height >= 100 }) {
                panel.setFrame(saved, display: false)
            } else { panel.setFrame(defaultFrame, display: false) }
        } else { panel.setFrame(defaultFrame, display: false) }
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Took Mac")
        statusItem.button?.toolTip = "Took Mac — 할 일을 툭"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("앱 열기", action: #selector(showMainWindow), key: "o"))
        menu.addItem(item("위젯 앞으로 가져오기", action: #selector(showWidget), key: "n"))
        visibilityItem = item("위젯 숨기기", action: #selector(toggleVisibility))
        menu.addItem(visibilityItem)
        menu.addItem(.separator())
        pinItem = item("항상 위에 표시", action: #selector(togglePin))
        menu.addItem(pinItem)
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

    func menuWillOpen(_ menu: NSMenu) {
        pinItem.state = preferences.alwaysOnTop ? .on : .off
        visibilityItem.title = panel.isVisible ? "위젯 숨기기" : "위젯 표시"
    }

    private func applyPreferences() {
        guard panel != nil else { return }
        panel.level = preferences.alwaysOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        let appearance: NSAppearance? = switch preferences.appearance {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        panel.appearance = appearance
        mainWindow.appearance = appearance
        if preferences.showDesktopWidget {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else { panel.orderOut(nil) }
        settingsWindow?.appearance = appearance
        updateCornerWatcher()
    }

    private func updateCornerWatcher() {
        guard preferences.openFromCorners else {
            cornerTimer?.invalidate()
            cornerTimer = nil
            cornerTrigger = ScreenCornerTrigger()
            return
        }
        guard cornerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.cornerTrigger.update(pointer: NSEvent.mouseLocation,
                                             screens: NSScreen.screens.map(\.frame),
                                             now: ProcessInfo.processInfo.systemUptime) {
                    self.showWidget()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cornerTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        cornerTimer?.invalidate()
    }

    @objc func showWidget() {
        preferences.showDesktopWidget = true
        panel.level = .floating
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleVisibility() {
        preferences.showDesktopWidget.toggle()
    }
    @objc private func togglePin() { preferences.alwaysOnTop.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 450),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Took Mac 설정"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, store: store))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.level = .floating
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) { applyPreferences() }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        guard panel != nil else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "widgetFrame")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
}

struct SettingsView: View {
    @ObservedObject var preferences: WidgetPreferences
    @ObservedObject var store: TaskStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Color(red: 0.97, green: 0.51, blue: 0.43))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Took Mac").font(.headline)
                    Text("바탕화면에서 하나씩, 가볍게.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("바탕화면 위젯 표시", isOn: $preferences.showDesktopWidget)
            Toggle("다른 창 위에 항상 표시", isOn: $preferences.alwaysOnTop)
            Text("끄면 다른 앱을 사용할 때 바탕화면 뒤에 머물러요.").font(.caption).foregroundStyle(.secondary)
            Toggle("화면 아래 모서리에서 위젯 열기", isOn: $preferences.openFromCorners)
            Text("왼쪽 아래나 오른쪽 아래에 마우스를 잠깐 두면 위젯이 나타나요.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            Text("할 일은 이 맥에만 저장돼요. 원본 Took 및 iCloud와는 연결되지 않아요.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("저장 폴더 열기") { NSWorkspace.shared.open(store.repository.fileURL.deletingLastPathComponent()) }
            Text("개인용 독립 프로젝트 · 버전 0.1.0").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(24).frame(width: 340)
            .alert("설정을 변경하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
    }
}
