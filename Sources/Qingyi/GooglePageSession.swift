import AppKit
import WebKit
import TranslationCore

@MainActor final class GooglePageSession: NSObject, WKNavigationDelegate {
    private weak var model: AppModel?
    private var page: WKWebView?
    private weak var renderHost: NSView?
    private var navigation: WKNavigation?
    private var ready = false
    private var languages = ""
    private var visible = false
    private var idleSince: Date?
    private var releaseTask: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var activeID: UUID?
    private var text = ""
    private var url: URL?
    private var requestedLanguages = ""
    private var reused = false
    private var inputConfirmed = false
    private var oldOutput = ""
    // Keep the proven direct navigation for short text; bound navigation URL size.
    private static let maximumNavigationBytes = 8_000
    private var injectAfterLoad = false
    private var navigationFinished = false
    private var encodedInput = ""
    private var injectionAttempts = 0
    private var lastInjection: Date?

    private var last: (text: String, languages: String, result: String)?
    private let pageFactory: @MainActor () -> WKWebView
    var hasRetainedPage: Bool { page != nil }
    init(model: AppModel, pageFactory: @escaping @MainActor () -> WKWebView = {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 840, height: 620), configuration: config)
    }) { self.model = model; self.pageFactory = pageFactory }
    func setPopupVisible(_ value: Bool) {
        visible = value
        if value { idleSince = nil; releaseTask?.cancel(); releaseTask = nil }
        else { scheduleRelease() }
    }
    func retentionChanged() { scheduleRelease() }
    private func scheduleRelease() {
        releaseTask?.cancel(); releaseTask = nil
        guard page != nil, !visible, activeID == nil, let model else { return }
        if idleSince == nil { idleSince = Date() }
        guard let delay = model.googlePageRetention.remaining(since: idleSince!, now: Date()) else { return }
        if delay <= 0 { releasePage(); return }
        releaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, !self.visible, self.activeID == nil else { return }
            self.releasePage()
        }
    }
    private func releasePage() {
        poller?.cancel(); poller = nil
        page?.stopLoading(); page?.navigationDelegate = nil; page?.removeFromSuperview()
        page = nil; navigation = nil; ready = false; last = nil; idleSince = nil
    }
    func cancelRequest() {
        let pending = activeID != nil
        activeID = nil; poller?.cancel(); poller = nil
        if pending { page?.stopLoading(); ready = false }
        scheduleRelease()
    }
    func attach(to host: NSView) {
        renderHost = host
        let view = getPage()
        if view.superview !== host { view.removeFromSuperview(); host.addSubview(view) }
        view.frame = NSRect(x: 0, y: 0, width: 840, height: 620)
    }
    func detach(from host: NSView) {
        guard renderHost === host else { return }
        page?.removeFromSuperview(); renderHost = nil
    }
    private func getPage() -> WKWebView {
        if let page { return page }
        let view = pageFactory()
        view.navigationDelegate = self; page = view
        if let renderHost { renderHost.addSubview(view); view.frame = NSRect(x: 0, y: 0, width: 840, height: 620) }
        return view
    }
    private func current(_ id: UUID) -> Bool {
        activeID == id && model?.webRequestID == id && model?.provider == .google
    }
    func translate(text: String, source: String, target: String, url: URL, requestID: UUID, forceRefresh: Bool = false) {
        cancelRequest(); releaseTask?.cancel(); releaseTask = nil; idleSince = nil
        // Textareas normalize CRLF/CR line endings; compare the same representation.
        let expectedText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        activeID = requestID; self.text = expectedText; self.url = url; requestedLanguages = source + "\u{0}" + target
        guard let data = try? JSONSerialization.data(withJSONObject: [expectedText]),
              let encoded = String(data: data, encoding: .utf8) else {
            fail("无法准备翻译文本，请重试。", id: requestID); return
        }
        encodedInput = encoded
        let view = getPage()
        oldOutput = last?.result ?? ""; reused = ready && languages == requestedLanguages; inputConfirmed = false
        if forceRefresh || !reused { load(view, id: requestID); return }
        let previous = last
        poller = Task { @MainActor [weak self, weak view] in
            guard let self, let view else { return }
            let state = try? await view.evaluateJavaScript(Self.snapshot) as? [String: Any]
            guard !Task.isCancelled, self.current(requestID) else { return }
            guard let state, let visibleOutput = state["text"] as? String else {
                self.load(view, id: requestID); return
            }
            if let previous, previous.text == expectedText, previous.languages == self.requestedLanguages,
               state["source"] as? String == expectedText, visibleOutput == previous.result,
               state["mode"] as? String == "Advanced", state["loading"] as? Bool == false {
                self.complete(previous.result, id: requestID); return
            }
            self.oldOutput = visibleOutput
            let updated = (try? await view.evaluateJavaScript(self.inputScript)) as? Bool ?? false
            guard !Task.isCancelled, self.current(requestID) else { return }
            if updated { self.poll(view, id: requestID) } else { self.load(view, id: requestID) }
        }
    }
    private var inputScript: String {
        """
        (() => {
          const box = document.querySelector('textarea[aria-label="Source text"]') || document.querySelector('textarea');
          const mode = document.querySelector('[aria-label="Text translation model"]');
          if (!box || (mode?.querySelector('[jsname="V67aGc"]')?.textContent || mode?.innerText || '').trim() !== 'Advanced') return false;
          const text = \(encodedInput)[0];
          Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(box, text);
          box.dispatchEvent(new Event('input', {bubbles:true}));
          box.dispatchEvent(new Event('change', {bubbles:true}));
          return box.value === text;
        })()
        """
    }
    private static let snapshot = """
    (() => {
      const mode = document.querySelector('[aria-label="Text translation model"]');
      const output = document.querySelector('[jsname="jqKxS"]');
      const loading = document.querySelector('.xsPT1b');
      const source = document.querySelector('textarea[aria-label="Source text"]') || document.querySelector('textarea');
      return {mode:(mode?.querySelector('[jsname="V67aGc"]')?.textContent || mode?.innerText || '').trim(),text:output?.innerText || '',source:source?.value || '',loading:loading ? getComputedStyle(loading).display !== 'none' : false,loadingKnown:!!loading,documentReady:document.readyState === 'complete',hasInput:!!source};
    })()
    """
    private func load(_ view: WKWebView, id: UUID) {
        guard current(id), let url else { return }
        model?.previewOutput = ""
        poller?.cancel(); poller = nil; reused = false; ready = false; navigationFinished = false
        injectionAttempts = 0; lastInjection = nil
        injectAfterLoad = url.absoluteString.utf8.count > Self.maximumNavigationBytes
        var navigationURL = url
        if injectAfterLoad {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { fail("无法准备翻译页面。", id:id); return }
            parts.queryItems = parts.queryItems?.filter { $0.name != "text" }
            guard let shortURL = parts.url else { fail("无法准备翻译页面。", id:id); return }
            navigationURL = shortURL
        }
        inputConfirmed = !injectAfterLoad
        view.stopLoading(); navigation = view.load(URLRequest(url: navigationURL))
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard response.isForMainFrame, let status = (response.response as? HTTPURLResponse)?.statusCode,
              status >= 400, let id = activeID, current(id) else { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        let hint = status == 429 ? "请求过于频繁，请稍后重试。" : "请重试或检查网络。"
        fail("Google 翻译页面请求失败（HTTP \(status)）。\(hint)", id:id)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === self.navigation, let id = activeID else { return }; poll(webView, id: id)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        navigationFinished = true
        if poller == nil, let id = activeID { poll(webView, id: id) }
    }
    private func poll(_ view: WKWebView, id: UUID) {
        poller?.cancel()
        poller = Task { @MainActor [weak self, weak view] in
            var stability = GoogleResultStability(); let start = Date(); var modeAttempts = 0; var readyObservations = 0
            var timeoutMessage = "Google 翻译页面未能就绪，请检查网络后重试。"
            for attempt in 0..<150 {
                guard !Task.isCancelled, let self, let view, self.current(id) else { return }
                if let data = try? await view.evaluateJavaScript(Self.snapshot) as? [String:Any] {
                    guard !Task.isCancelled, self.current(id) else { return }
                    let mode = data["mode"] as? String ?? "", output = data["text"] as? String ?? ""
                    let source = data["source"] as? String ?? "", loading = data["loading"] as? Bool ?? true
                    let matching = source == self.text
                    if self.navigationFinished && data["documentReady"] as? Bool == true && data["hasInput"] as? Bool == true {
                        if mode.isEmpty {
                            timeoutMessage = "Google 页面未提供 Advanced 模式，请重试。"
                        } else if mode != "Advanced" {
                            timeoutMessage = "Google 当前没有选择 Advanced 模式。请检查原文和目标语言。"
                        } else if !matching {
                            timeoutMessage = "Google 页面未能接收或保留输入文字，请重试。"
                        } else {
                            timeoutMessage = "Google 高级翻译未在等待时间内返回译文，请重试。"
                        }
                    } else {
                        timeoutMessage = "Google 翻译页面未能就绪，请检查网络后重试。"
                    }
                    if matching && (loading || output.isEmpty || output != self.oldOutput) { self.inputConfirmed = true }
                    if self.injectAfterLoad, !matching {
                        self.inputConfirmed = false; stability = GoogleResultStability()
                        let writable = self.navigationFinished && data["documentReady"] as? Bool == true && data["hasInput"] as? Bool == true && mode == "Advanced"
                        readyObservations = writable ? readyObservations + 1 : 0
                        if readyObservations >= 2, self.lastInjection.map({ Date().timeIntervalSince($0) >= 0.8 }) ?? true {
                            guard self.injectionAttempts < 3 else { self.fail("Google 页面未能保留输入文字，请重试。", id:id); return }
                            self.oldOutput = output
                            self.injectionAttempts += 1; self.lastInjection = Date()
                            _ = try? await view.evaluateJavaScript(self.inputScript)
                            guard !Task.isCancelled, self.current(id) else { return }
                        }
                    }
                    if mode == "Classic", attempt >= 5, modeAttempts < 3 {
                        let changed = (try? await view.evaluateJavaScript(Self.selectAdvanced)) as? String ?? "unavailable"
                        guard !Task.isCancelled, self.current(id) else { return }
                        if changed == "requested" { modeAttempts += 1; stability = GoogleResultStability() }
                        // Opening a native page menu and choosing the option occur
                        // in separate DOM turns; never accept Classic output.
                    }
                    // A loading transition can acknowledge the input while the prior result is still visible.
                    let freshOutput = !self.reused || (output != self.oldOutput && output != self.last?.result)
                    if self.reused, Date().timeIntervalSince(start) >= 3, (!matching || !self.inputConfirmed || !freshOutput) {
                        self.load(view, id:id); return
                    }
                    let eligible = mode == "Advanced" && matching && self.inputConfirmed && freshOutput
                    let preview = eligible && !loading ? output : ""
                    if let model = self.model, model.previewOutput != preview {
                        model.previewOutput = preview
                    }
                    if stability.observe(text: output, advanced: eligible, loading: loading,
                                         loadingKnown: data["loadingKnown"] as? Bool ?? false, now: Date().timeIntervalSinceReferenceDate) {
                        self.complete(output, id:id); return
                    }
                    if attempt >= 125, !mode.isEmpty, mode != "Advanced" { self.fail("Google 当前没有选择 Advanced 模式。请检查原文和目标语言。", id:id); return }
                }
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            }
            self?.fail(timeoutMessage, id:id)
        }
    }
    private static let selectAdvanced = """
    (() => {
      const button = document.querySelector('[aria-label="Text translation model"]');
      if (!button) return 'unavailable';
      const options = Array.from(document.querySelectorAll('[role="menuitemradio"]'));
      const advanced = options.find(el => el.querySelector('[jsname="K4r5Ff"]')?.textContent?.trim() === 'Advanced');
      if (button.getAttribute('aria-expanded') !== 'true') { button.click(); return 'opening'; }
      if (!advanced || advanced.getAttribute('aria-disabled') === 'true') return 'unavailable';
      if (advanced.getAttribute('aria-checked') === 'true') { button.click(); return 'selected'; }
      advanced.click(); return 'requested';
    })()
    """
    private func complete(_ result: String, id: UUID) {
        guard current(id), let model else { return }
        last = (text, requestedLanguages, result); ready = true; languages = requestedLanguages
        model.output = result; model.previewOutput = ""; model.busy = false; activeID = nil; poller = nil; scheduleRelease()
    }
    private func fail(_ message: String, id: UUID) {
        guard current(id), let model else { return }
        model.error = message; model.previewOutput = ""; model.busy = false; activeID = nil
        poller?.cancel(); poller = nil; ready = false; scheduleRelease()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(navigation, error:error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(navigation, error:error) }
    private func failed(_ navigation: WKNavigation?, error: Error) {
        guard navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled, let id = activeID else { return }
        fail("无法连接 Google 翻译，请检查网络后重试。", id:id)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        page?.removeFromSuperview(); ready = false; page = nil; last = nil
        if let id = activeID { load(getPage(), id:id) } else { scheduleRelease() }
    }
}
