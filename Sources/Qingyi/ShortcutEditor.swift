import AppKit
import SwiftUI

private typealias EditorState<Value> = SwiftUI.State<Value>

struct ShortcutEditor: View {
    @ObservedObject var model: AppModel
    @EditorState<SelectionShortcut?> private var candidate: SelectionShortcut?
    @EditorState<String?> private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置划词快捷键").font(.headline)
            Text("按下修饰键和一个普通按键，再点“完成”。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(candidate?.title ?? "请按下组合键…")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .overlay { ShortcutCapture(onKey: capture, onCancel: cancel).frame(width: 1, height: 1) }
            Text(message ?? "按 Esc 取消。录入期间不会触发翻译。")
                .font(.caption).foregroundStyle(message == nil ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("恢复默认") { candidate = .controlOptionT; message = nil }
                Spacer()
                Button("取消", action: cancel)
                Button("完成") {
                    guard let candidate else { return }
                    if model.applyShortcut(candidate) { cancel() }
                    else { message = model.hotkeyWarning }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(candidate == nil)
            }
        }
        .padding(24).frame(width: 370)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cancel() }
        .onDisappear { model.recordingShortcut = false }
    }
    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let value = SelectionShortcut.capture(event)
        if let error = value.validationError { candidate = nil; message = error }
        else { candidate = value; message = nil }
    }
    private func cancel() { model.recordingShortcut = false }
}

private struct ShortcutCapture: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    let onCancel: () -> Void
    final class CaptureView: NSView {
        var monitor: Any?
        var onKey: ((NSEvent) -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, NSApp.keyWindow === window else { return event }
                if event.keyCode == 53 { self.onCancel?(); return nil }
                // Let Tab retain its normal focus-navigation behavior.
                if event.keyCode == 48 || event.keyCode == 36 { return event }
                self.onKey?(event); return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { stop() }
    }
    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView(); view.onKey = onKey; view.onCancel = onCancel; view.start()
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }; view.window?.makeFirstResponder(view)
        }
        return view
    }
    func updateNSView(_ view: CaptureView, context: Context) { view.onKey = onKey; view.onCancel = onCancel }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stop() }
}
