import AppKit
import SwiftUI

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TranslationHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) { return hit }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private func makeMenuBarIcon() -> NSImage {
    let size = NSSize(width: 24, height: 18)
    let image = NSImage(size: size, flipped: true) { _ in
        NSColor.black.setStroke()
        let front = NSBezierPath()
        front.lineWidth = 1.2
        front.lineJoinStyle = .round
        front.move(to: NSPoint(x: 11.2, y: 6.0))
        front.line(to: NSPoint(x: 19.0, y: 6.0))
        front.curve(to: NSPoint(x: 22.0, y: 9.0), controlPoint1: NSPoint(x: 20.8, y: 6), controlPoint2: NSPoint(x: 22, y: 7.2))
        front.line(to: NSPoint(x: 22, y: 13.0))
        front.curve(to: NSPoint(x: 19, y: 16.0), controlPoint1: NSPoint(x: 22, y: 14.8), controlPoint2: NSPoint(x: 20.8, y: 16))
        front.line(to: NSPoint(x: 19, y: 17.4)); front.line(to: NSPoint(x: 16.7, y: 16)); front.line(to: NSPoint(x: 12.2, y: 16))
        front.curve(to: NSPoint(x: 9.3, y: 13), controlPoint1: NSPoint(x: 10.4, y: 16), controlPoint2: NSPoint(x: 9.3, y: 14.8))
        front.line(to: NSPoint(x: 9.3, y: 10.7)); front.stroke()
        let back = NSBezierPath()
        back.lineWidth = 1.2; back.lineJoinStyle = .round
        back.move(to: NSPoint(x: 4.0, y: 1.0)); back.line(to: NSPoint(x: 11.0, y: 1.0))
        back.curve(to: NSPoint(x: 14.0, y: 4.0), controlPoint1: NSPoint(x: 12.8, y: 1), controlPoint2: NSPoint(x: 14, y: 2.2))
        back.line(to: NSPoint(x: 14, y: 7.6))
        back.curve(to: NSPoint(x: 11, y: 10.6), controlPoint1: NSPoint(x: 14, y: 9.4), controlPoint2: NSPoint(x: 12.8, y: 10.6))
        back.line(to: NSPoint(x: 7.3, y: 10.6)); back.line(to: NSPoint(x: 4.7, y: 12.5)); back.line(to: NSPoint(x: 4.7, y: 10.6))
        back.line(to: NSPoint(x: 4, y: 10.6))
        back.curve(to: NSPoint(x: 1, y: 7.6), controlPoint1: NSPoint(x: 2.2, y: 10.6), controlPoint2: NSPoint(x: 1, y: 9.4))
        back.line(to: NSPoint(x: 1, y: 4))
        back.curve(to: NSPoint(x: 4, y: 1), controlPoint1: NSPoint(x: 1, y: 2.2), controlPoint2: NSPoint(x: 2.2, y: 1))
        back.close(); back.stroke()
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6.5, weight: .semibold), .foregroundColor: NSColor.black, .paragraphStyle: centered]
        ("A" as NSString).draw(in: NSRect(x: 3, y: 1.8, width: 9, height: 8), withAttributes: attributes)
        ("文" as NSString).draw(in: NSRect(x: 12, y: 7.2, width: 8, height: 8), withAttributes: attributes)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "轻译"
    return image
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyManager()
    private var glassPanel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var sourcePID: pid_t?
    private var settingsWindow: NSWindow?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        lastExternalApplication = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in
                guard let self else { return }
                if self.glassPanel?.isVisible == true, let sourcePID = self.sourcePID, sourcePID != app.processIdentifier {
                    self.closePanel()
                }
                self.lastExternalApplication = app
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.toolTip = "轻译 · 选中文字后按 \(model.shortcut.title)"
        }
        let menu = NSMenu()
        menu.delegate = self
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let diagnostics = NSMenuItem(title: "打开诊断日志…", action: #selector(openDiagnostics), keyEquivalent: "")
        diagnostics.target = self; menu.addItem(diagnostics)
        let quit = NSMenuItem(title: "退出轻译", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        hotkeys.onPress = { [weak self] _ in self?.translateSelection() }
        model.shortcutChanged = { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.toolTip = "轻译 · 选中文字后按 \(self.model.shortcut.title)"
        }
        model.registerShortcut = { [weak self] value in
            guard let self else { return "快捷键服务不可用。" }
            return self.hotkeys.register(selection: value)
        }
        model.shortcutRecordingChanged = { [weak self] value in
            guard let self else { return }
            if let warning = self.hotkeys.setRecording(value) { self.model.hotkeyWarning = warning }
        }
        registerHotkey()
        if !AXIsProcessTrusted() { openSettings() }
    }
    private func registerHotkey() {
        model.hotkeyWarning = hotkeys.register(selection: model.shortcut)
        statusItem?.button?.toolTip = "轻译 · 选中文字后按 \(model.shortcut.title)"
    }
    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出轻译", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    @objc func translateSelection() {
        // Read the source application before activating the translation panel.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let app = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApplication : frontmost
        sourcePID = app?.processIdentifier
        closePanel()
        do {
            let text = try SystemCapture.selection(in: app)
            model.accept(text, origin: app?.localizedName ?? "选中文字")
        } catch {
            model.input = ""
            model.error = error.localizedDescription
        }
        showPanel()
    }
    private func showPanel() {
        model.beginArchiveSession()
        model.setPopupVisible(true)
        stopMonitoring()
        let sourceApp = sourcePID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let cursor = NSEvent.mouseLocation
        let selection = SystemCapture.selectionBounds(in: sourceApp) ?? NSRect(x: cursor.x, y: cursor.y, width: 2, height: 2)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? selection.insetBy(dx: -400, dy: -400)
        let anchorRect = selection.intersection(visible)
        let bounds = anchorRect.isNull || anchorRect.isEmpty ? NSRect(x: cursor.x, y: cursor.y, width: 2, height: 2) : anchorRect

        let placement = Self.placement(for: bounds, in: visible)
        let size = placement.panelSize

        // A borderless panel with a real `glassEffect` surface. NSPopover is not an
        // option here: its frame is a private NSPopoverFrame wrapping an
        // NSVisualEffectView that still uses the deprecated appearance-based
        // material (rawValue 0). That material can't be replaced or re-stated from
        // outside, so a popover always renders the old grey blur instead of Liquid
        // Glass, no matter what tint or state the content applies.
        let panel = TranslationPanel(contentRect: NSRect(origin: placement.origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Keep the transparent popup free of a rectangular window shadow.
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let host = TranslationHostingView(rootView: TranslationView(model: model,
            settings: { [weak self] in self?.openSettings() }, close: { [weak self] in self?.closePanel() },
            tail: placement.tail, tailOffset: placement.tailOffset))
        // No layer mask here: the glass draws its own rounded shape including the
        // tail, and masking the hosting view to a rounded rect would clip the tail
        // off. The native window shadow is disabled for this popup.
        //
        // Focus ring must be switched off at the AppKit level. `.focusEffectDisabled()`
        // in SwiftUI only suppresses SwiftUI's own focus effect; the ring for the
        // view that actually holds first responder is drawn by AppKit, and on this
        // panel that is the hosting view itself. Left on, it traces a hard dashed
        // rectangle around the window bounds instead of following the rounded glass.
        host.focusRingType = .none
        // No layer-level mask here. A `cornerRadius` + `masksToBounds` clip uses
        // the bounding rectangle, which cuts the tail off at the panel edge — the
        // silhouette is the SwiftUI `BubbleShape`, not a rounded rect. Anything
        // that needs clipping is handled inside `popupGlass()`, which clips to
        // that exact shape.
        host.wantsLayer = true
        panel.contentView = host
        glassPanel = panel

        // Liquid Glass has a dimmed look whenever its window is not key, and a
        // `glassEffect` surface is no exception: leaving the panel unfocused
        // gives exactly the grey, flat popup users complain about. So this panel
        // does take focus while it is open. It is borderless with no titlebar and
        // no focus ring, so visually it still reads as a floating overlay rather
        // than a window the user switched to, and `closePanel()` hands focus back
        // to the app the user was reading in.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let panel = self.glassPanel, panel.isVisible else { return }
            self.startMonitoring()
        }
    }

    /// Where to put the panel and which way its tail should point.
    private struct Placement {
        var origin: NSPoint
        var panelSize: NSSize
        var tail: BubbleTail
        /// Tail centre along its edge, measured from the panel's leading side.
        var tailOffset: CGFloat
    }

    private static let contentSize = NSSize(width: 360, height: 345)
    private static let panelGap: CGFloat = 8
    private static let tailLength: CGFloat = 14

    /// Places the panel below the selection when there is room, otherwise above,
    /// and clamps it inside the screen. The tail always points back at the
    /// selection, matching how the system translation popover is attached.
    private static func placement(for bounds: NSRect, in visible: NSRect) -> Placement {
        let content = contentSize
        let gap = panelGap

        // Try below the selection (tail on top, pointing up at the text).
        let belowHeight = content.height + tailLength
        var y = bounds.minY - gap - belowHeight
        var tail: BubbleTail = .top

        if y < visible.minY + 8 {
            // No room below: sit above the selection with the tail pointing down.
            y = bounds.maxY + gap
            tail = .bottom
            if y + belowHeight > visible.maxY - 8 {
                // Neither side fits; fall back to centring and drop the tail
                // rather than pointing at empty space.
                y = max(visible.minY + 8, min(y, visible.maxY - belowHeight - 8))
                tail = .none
            }
        }

        let width = content.width
        var x = bounds.midX - width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - width - 8))

        let panelSize = NSSize(width: width, height: content.height + (tail == .none ? 0 : tailLength))
        let offset = bounds.midX - x
        return Placement(origin: NSPoint(x: x, y: y),
                         panelSize: panelSize,
                         tail: tail,
                         tailOffset: offset)
    }

    private func startMonitoring() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.glassPanel, panel.isVisible else { return }
                // Taps on the panel itself belong to its own controls.
                if panel.frame.contains(NSEvent.mouseLocation) || self.model.providerMenuPresented { return }
                self.closePanel()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, let panel = self.glassPanel, panel.isVisible else { return event }
            // SwiftUI presents the provider picker in a separate popover window.
            // Its option clicks are part of the translation UI, not outside clicks.
            if event.window !== panel && !self.model.providerMenuPresented { self.closePanel() }
            return event
        }
    }
    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
    private func closePanel() {
        stopMonitoring()
        let current = glassPanel; glassPanel = nil
        model.cancel(); model.setPopupVisible(false)
        current?.orderOut(nil); current?.close()
        // Give focus back to whatever the user was reading in; without this the
        // app stays "active" with no window and the next keystroke goes nowhere.
        if let previous = lastExternalApplication, !previous.isTerminated {
            previous.activate(options: [])
        }
    }
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 555),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "轻译设置"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            // The glass fills the whole window, titlebar included, so there is no
            // opaque chrome band and no seam where a rounded content view meets a
            // square window edge. Traffic lights float over the glass the way they
            // do in the system's own glass windows. The content view insets itself
            // below the titlebar, so nothing hides under the buttons.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            // Match the glass radius so the window's own shadow follows the
            // rounded corners instead of tracing a square frame.
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 12
            window.contentView?.layer?.cornerCurve = .continuous
            window.contentView?.layer?.masksToBounds = true
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    @objc private func openDiagnostics() {
        let file = GoogleDiagnostics.file
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            let alert = NSAlert()
            alert.messageText = "暂无 Google 翻译诊断日志"
            alert.informativeText = "使用一次 Google 翻译后，再从菜单打开日志。"
            alert.runModal()
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
