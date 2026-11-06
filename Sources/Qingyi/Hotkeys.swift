import AppKit
import Carbon

struct SelectionShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let controlOptionT = SelectionShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))
    static func load(from defaults: UserDefaults) -> SelectionShortcut {
        if let data = defaults.data(forKey: "customShortcut"), let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        let code = [UInt32(kVK_ANSI_T), UInt32(kVK_ANSI_Y), UInt32(kVK_Space)]
        let legacy = defaults.integer(forKey: "shortcut")
        return Self(keyCode: code.indices.contains(legacy) ? code[legacy] : code[0], modifiers: UInt32(controlKey | optionKey))
    }
    var title: String {
        var prefix = ""
        for (mask, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(mask) != 0 { prefix += symbol }
        }
        return prefix + keyName
    }
    private var keyName: String {
        if keyCode == UInt32(kVK_Space) { return "Space" }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0; var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            if status == noErr, length > 0 { return String(utf16CodeUnits: chars, count: length).uppercased() }
        }
        return "Key \(keyCode)"
    }
    static func capture(_ event: NSEvent) -> Self {
        var modifiers: UInt32 = 0
        for (flag, mask) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if event.modifierFlags.contains(flag) { modifiers |= UInt32(mask) }
        }
        return Self(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
    var validationError: String? {
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return "请包含 Control、Option 或 Command，再加一个普通按键。" }
        guard keyCode <= 50, ![UInt32(kVK_Return), UInt32(kVK_Tab), UInt32(kVK_Delete)].contains(keyCode) else { return "暂不支持这个按键，请使用字母、数字、标点或空格。" }
        let commandKeys = [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_Space, kVK_Tab]
        if modifiers == UInt32(cmdKey), commandKeys.map({ UInt32($0) }).contains(keyCode) { return "这个组合用于常见系统操作，请换一个。" }
        if keyCode == UInt32(kVK_Space), [UInt32(controlKey), UInt32(controlKey | optionKey), UInt32(cmdKey | optionKey), UInt32(controlKey | cmdKey)].contains(modifiers) { return "这个组合通常用于输入法、Spotlight 或表情面板，请换一个。" }
        return nil
    }
}

@MainActor final class HotkeyManager {
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    var onPress: ((UInt32) -> Void)?
    private var active: SelectionShortcut?
    private var recording = false
    private var held = false
    private let registerKey: (SelectionShortcut, inout EventHotKeyRef?) -> OSStatus
    private let unregisterKey: (EventHotKeyRef) -> Void
    init(registerKey: @escaping (SelectionShortcut, inout EventHotKeyRef?) -> OSStatus = { selection, ref in
        RegisterEventHotKey(selection.keyCode, selection.modifiers, EventHotKeyID(signature: 0x51494E47, id: 1), GetApplicationEventTarget(), 0, &ref)
    }, unregisterKey: @escaping (EventHotKeyRef) -> Void = { _ = UnregisterEventHotKey($0) }) {
        self.registerKey = registerKey; self.unregisterKey = unregisterKey
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            let pressedID = id.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            Task { @MainActor in
                if released { manager.held = false; return }
                guard !manager.recording, !manager.held else { return }
                manager.held = true; manager.onPress?(pressedID)
            }
            return noErr
        }, 2, &specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func setRecording(_ value: Bool) -> String? {
        recording = value; held = false
        if value { refs.forEach { unregisterKey($0) }; refs.removeAll(); return nil }
        guard refs.isEmpty, let active else { return nil }
        return register(selection: active)
    }
    func register(selection: SelectionShortcut) -> String? {
        if selection == active, !refs.isEmpty { return nil }
        var ref: EventHotKeyRef?
        let status = registerKey(selection, &ref)
        guard status == noErr, let ref else {
            return "无法使用 \(selection.title)，可能已被系统或其他应用占用（\(status)）。原设置未更改。"
        }
        refs.forEach { unregisterKey($0) }
        refs = [ref]; active = selection
        return nil
    }
}
