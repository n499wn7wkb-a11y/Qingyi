import AppKit
import SwiftUI

/// Keep service selection in a single native menu tracking session. Rebuild the
/// menu each time, and start translation only after tracking has fully ended.
struct ProviderMenuButton: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> HoverButton {
        let button = HoverButton()
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "切换翻译服务")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("切换翻译服务")
        button.toolTip = "切换翻译服务"
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        return button
    }
    func updateNSView(_ button: HoverButton, context: Context) { context.coordinator.model = model }
    final class HoverButton: NSButton {
        private var area: NSTrackingArea?
        var menuTracking = false { didSet { needsDisplay = true } }
        private var hovering = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            area = new; addTrackingArea(new); super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            if hovering || menuTracking || isHighlighted {
                NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.15 : 0.08).setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
            }
            super.draw(dirtyRect)
        }
    }
    @MainActor final class Coordinator: NSObject {
        var model: AppModel
        private var selected: TranslationProvider?
        init(model: AppModel) { self.model = model }
        @objc func openMenu(_ sender: HoverButton) {
            guard !model.providerMenuPresented else { return }
            model.refreshAvailableProviders()
            let menu = NSMenu()
            menu.autoenablesItems = false
            for provider in model.availableProviders {
                let item = NSMenuItem(title: provider.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = provider.rawValue
                item.state = provider == model.provider ? .on : .off
                menu.addItem(item)
            }
            selected = nil
            model.providerMenuPresented = true; sender.menuTracking = true
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
            // Native menu tracking is synchronous, including outside-click and
            // Escape dismissal. No SwiftUI popover binding can remain stale.
            model.providerMenuPresented = false; sender.menuTracking = false
            if let selected { model.switchProvider(selected) }
            selected = nil
        }
        @objc private func choose(_ item: NSMenuItem) {
            guard let raw = item.representedObject as? String else { return }
            selected = TranslationProvider(rawValue: raw)
        }
    }
}
