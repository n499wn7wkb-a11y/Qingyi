import Foundation

/// Shorten the quiet period only when the page exposes its loading indicator.
/// Unknown page structure retains the previous two-second safeguard.
public struct GoogleResultStability {
    private var last = ""
    private var unchangedSince: TimeInterval?
    public init() {}
    public mutating func observe(text: String, advanced: Bool, loading: Bool, loadingKnown: Bool, now: TimeInterval) -> Bool {
        guard advanced, !loading, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            last = ""; unchangedSince = nil; return false
        }
        if text != last || unchangedSince == nil { last = text; unchangedSince = now; return false }
        return now - unchangedSince! >= (loadingKnown ? 0.6 : 2.0)
    }
}
