import AppKit
import SwiftUI

/// Keep a real window-backed rendering surface while a translation is visible.
/// The session owns the page, so removing this host does not discard the page.
struct GooglePageHost: NSViewRepresentable {
    let session: GooglePageSession
    final class Host: NSView { weak var session: GooglePageSession? }
    func makeNSView(context: Context) -> Host {
        let view = Host(); view.session = session; session.attach(to: view); return view
    }
    func updateNSView(_ view: Host, context: Context) { session.attach(to: view) }
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.session?.detach(from: view) }
}
