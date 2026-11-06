private func require(_ condition: @autoclosure () -> Bool, _ message: String = "check failed") {
    guard condition() else { fatalError(message) }
}
import AppKit
import Carbon
@main struct Check {
    @MainActor static func main() {
        let strong = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        require(SelectionShortcut.controlOptionT.validationError == nil)
        require(SelectionShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)).validationError != nil)
        require(SelectionShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)).validationError != nil)
        require(SelectionShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(shiftKey)).validationError != nil)
        let custom = SelectionShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
        require(custom.validationError == nil)
        let data = try! JSONEncoder().encode(custom)
        require(try! JSONDecoder().decode(SelectionShortcut.self, from: data) == custom)
        let defaults = UserDefaults(suiteName: "qingyi-shortcut-validation")!
        for index in 0...2 {
            defaults.setVolatileDomain(["shortcut": index], forName: UserDefaults.argumentDomain)
            let expected = [kVK_ANSI_T, kVK_ANSI_Y, kVK_Space][index]
            require(SelectionShortcut.load(from: defaults).keyCode == UInt32(expected))
        }
        let reserved = SelectionShortcut(keyCode: UInt32(kVK_F18), modifiers: strong)
        let old = SelectionShortcut(keyCode: UInt32(kVK_F19), modifiers: strong)
        var registrations: [UInt32: EventHotKeyRef] = [:]
        var counter = 1
        let register: (SelectionShortcut, inout EventHotKeyRef?) -> OSStatus = { shortcut, ref in
            guard registrations[shortcut.keyCode] == nil else { return OSStatus(eventHotKeyExistsErr) }
            ref = EventHotKeyRef(bitPattern: counter); counter += 1
            registrations[shortcut.keyCode] = ref
            return noErr
        }
        let unregister: (EventHotKeyRef) -> Void = { ref in registrations = registrations.filter { $0.value != ref } }
        let owner = HotkeyManager(registerKey: register, unregisterKey: unregister)
        let changing = HotkeyManager(registerKey: register, unregisterKey: unregister)
        let probe = HotkeyManager(registerKey: register, unregisterKey: unregister)
        require(owner.register(selection: reserved) == nil)
        require(changing.register(selection: old) == nil)
        require(changing.register(selection: reserved) != nil)
        require(probe.register(selection: old) != nil, "Old shortcut must stay registered after a failed replacement")
        require(changing.setRecording(true) == nil)
        require(changing.setRecording(false) == nil)
        require(changing.register(selection: old) == nil)
        print("PASS: validation, encoding, 3 legacy migrations, registration conflict rollback with simulated OS responses, recording restoration")
    }
}
