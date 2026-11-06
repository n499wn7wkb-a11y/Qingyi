import AppKit
import ApplicationServices

enum CaptureFailure: LocalizedError {
    case accessibility, noSelection, secureField
    var errorDescription: String? {
        switch self {
        case .accessibility: return "请先为轻译开启辅助功能权限，以读取你选中的文字。"
        case .noSelection: return "未能读取选中文字。请重新选中后再试；部分应用可能不支持系统划词。"
        case .secureField: return "当前是密码输入框，请在普通文本区域使用翻译。"
        }
    }
}

@MainActor enum SystemCapture {
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func focusedElement(in app: NSRunningApplication?) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw CaptureFailure.accessibility }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw CaptureFailure.noSelection }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: axApp),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw CaptureFailure.noSelection }
        let element = value as! AXUIElement
        if (attribute(kAXSubroleAttribute, of: element) as? String) == (kAXSecureTextFieldSubrole as String) {
            throw CaptureFailure.secureField
        }
        return element
    }
    private static func candidates(from focused: AXUIElement, safari: Bool) -> [AXUIElement] {
        var result = [focused]
        guard safari else { return result }
        let role = attribute(kAXRoleAttribute, of: focused) as? String
        // Never substitute a page selection for the selection in an editable field.
        guard role != (kAXTextFieldRole as String), role != (kAXTextAreaRole as String) else { return result }
        var current = focused
        for _ in 0..<12 {
            guard let parent = attribute(kAXParentAttribute, of: current), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            let next = parent as! AXUIElement
            if CFEqual(next, current) { break }
            result.append(next); current = next
        }
        return result
    }
    private static func selectionData(_ element: AXUIElement) -> (String, CFTypeRef?, Bool)? {
        if let text = attribute(kAXSelectedTextAttribute, of: element) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let range = attribute(kAXSelectedTextRangeAttribute, of: element) { return (text, range, false) }
            if let marker = attribute("AXSelectedTextMarkerRange", of: element) { return (text, marker, true) }
            return (text, nil, false)
        }
        // WebKit exposes web selections as text-marker ranges. These are system
        // accessibility attributes, not clipboard contents or page JavaScript.
        guard let marker = attribute("AXSelectedTextMarkerRange", of: element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, marker, &value) == .success,
              let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (text, marker, true)
    }
    static func selectionBounds(in app: NSRunningApplication?) -> NSRect? {
        guard let focused = try? focusedElement(in: app) else { return nil }
        for element in candidates(from: focused, safari: app?.bundleIdentifier == "com.apple.Safari") {
            guard let (_, range, isMarker) = selectionData(element), let range else { continue }
            let parameter = isMarker ? "AXBoundsForTextMarkerRange" : kAXBoundsForRangeParameterizedAttribute
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, parameter as CFString, range, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { continue }
            var bounds = CGRect.zero
            guard AXValueGetValue(value as! AXValue, .cgRect, &bounds), bounds.width > 0, bounds.height > 0,
                  let primary = NSScreen.screens.first else { continue }
            let rect = NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
            if rect.origin.x.isFinite, rect.origin.y.isFinite, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return rect }
        }
        return nil
    }
    static func selection(in app: NSRunningApplication?) throws -> String {
        let focused = try focusedElement(in: app)
        for element in candidates(from: focused, safari: app?.bundleIdentifier == "com.apple.Safari") {
            if let (text, _, _) = selectionData(element) { return text }
        }
        throw CaptureFailure.noSelection
    }
}
