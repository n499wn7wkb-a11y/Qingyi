private func require(_ condition: @autoclosure () -> Bool, _ message: String = "check failed") {
    guard condition() else { fatalError(message) }
}
import Foundation
import WebKit
@MainActor final class NoNetworkWebView: WKWebView {
 var loads = 0
 override func load(_ request: URLRequest) -> WKNavigation? { loads += 1; return nil }
}
@main struct Check {
 @MainActor static func main() async throws {
    let suite = "QingyiTest-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var keyReads = 0
    let model = AppModel(defaults: defaults, keyReader: { _ in
        keyReads += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        return ""
    }, configuredReader: { [.deepSeek, .custom] })
    let page = NoNetworkWebView()
    model.googlePageSession = GooglePageSession(model: model, pageFactory: { page })
    model.setPopupVisible(true)
    model.provider = .deepSeek
    model.input = "A short test sentence."
    model.output = "old result"
    let oldID = model.webRequestID
    model.switchProvider(.google)
    require(model.provider == .google)
    require(model.output.isEmpty && model.busy)
    require(model.webURL?.host == "translate.google.com")
    require(model.webRequestID != oldID)
    require(model.webURL?.query?.contains("A%20short%20test%20sentence.") == true)
    let firstID = model.webRequestID
    model.output = "stale result"
    model.switchProvider(.google)
    require(model.output.isEmpty && model.busy && model.webRequestID != firstID)
    let secondID = model.webRequestID
    model.cancel()
    require(model.webRequestID != secondID && model.webURL == nil && !model.busy)
    model.setPopupVisible(false)
    let requests = page.loads
    model.source = "fr"; model.target = "en"
    model.switchProvider(.google)
    require(page.loads == requests && !model.busy, "Closed popup must not submit old text")
    model.setPopupVisible(true)
    model.target = "zh-CN"
    require(page.loads == requests + 1 && model.busy, "Visible popup must retranslate after language change")
    model.cancel(); model.setPopupVisible(false)
    for _ in 0..<10 { model.refreshAvailableProviders() }
    try await Task.sleep(nanoseconds: 150_000_000)
    require(keyReads == 0, "Provider menu must not read secret values")
    require(model.availableProviders == [.google, .deepSeek], "Unconfigured and invalid custom services must be hidden")
    defaults.set("https://example.com/v1", forKey: "endpoint.custom")
    model.refreshAvailableProviders()
    require(model.availableProviders.contains(.custom), "Valid configured custom service should be available")
    model.provider = .deepSeek; model.loadProviderSettings()
    require(model.keyLoading && !model.saveProviderSettings(), "Cannot save a blank key while loading")
    model.apiKey = "new draft"
    try await Task.sleep(nanoseconds: 150_000_000)
    require(model.apiKey == "new draft" && !model.keyLoading, "Late key read must preserve user edits")
    let before = keyReads
    model.accept("Cancel before key retrieval completes", origin: "test")
    model.cancel(); model.setPopupVisible(false)
    try await Task.sleep(nanoseconds: 200_000_000)
    require(!model.busy && model.output.isEmpty && model.error == nil, "Cancelled key retrieval must not start translation")
    require(keyReads <= before + 1)
    model.provider = .openAI; model.loadProviderSettings()
    model.provider = .google; model.loadProviderSettings()
    try await Task.sleep(nanoseconds: 150_000_000)
    require(model.apiKey.isEmpty && !model.keyLoading, "Late key read must not populate another provider")
    print("PASS privacy, async key loading, cancellation, provider availability, draft protection")
    print("PASS: service switch clears old output, starts new request for current text, same-service retry, invalidates cancelled request; no network requests issued")
 }
}
