import AppKit
import WebKit

final class Scheme: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url!
        let fields = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        let text = fields.first { $0.name == "text" }?.value ?? ""
        let target = fields.first { $0.name == "tl" }?.value ?? ""
        let values = String(data:try! JSONSerialization.data(withJSONObject:[text,target]),encoding:.utf8)!
        let html = """
        <button aria-label="Text translation model">Advanced</button>
        <textarea aria-label="Source text"></textarea><div class="xsPT1b"></div><div jsname="jqKxS"></div>
        <script>
        const box=document.querySelector('textarea'), spin=document.querySelector('.xsPT1b'), out=document.querySelector('[jsname="jqKxS"]'), mode=document.querySelector('button');
        const [input,target]=\(values);
        box.value=input;
        function update() { spin.style.display='none'; out.innerText='译文 '+target+': '+box.value; }
        update();
        if(input==='unknown-loader') spin.remove();
        if(input==='classic-only') mode.innerText='Classic';
        if(input==='wrong-source') box.value='different';
        box.addEventListener('input',update);
        </script>
        """
        task.didReceive(URLResponse(url:url,mimeType:"text/html",expectedContentLength:html.utf8.count,textEncodingName:"utf-8"))
        task.didReceive(Data(html.utf8)); task.didFinish()
    }
    func webView(_ webView:WKWebView,stop task:WKURLSchemeTask) {}
}

@MainActor final class LocalPage: WKWebView {
    override func load(_ request:URLRequest)->WKNavigation? {
        var parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
        parts.scheme="fixture"
        return super.load(URLRequest(url:parts.url!))
    }
}

struct PreviewRegression {
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        let model=AppModel(defaults:UserDefaults(suiteName:"PreviewFixture-"+UUID().uuidString)!,keyReader:{_ in ""},configuredReader:{[]})
        let handler=Scheme()
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.setURLSchemeHandler(handler,forURLScheme:"fixture")
        let page=LocalPage(frame:NSRect(x:0,y:0,width:840,height:620),configuration:config)
        let session=GooglePageSession(model:model,pageFactory:{page})
        model.googlePageSession=session
        let host=NSView(frame:NSRect(x:0,y:0,width:840,height:620))
        let window=NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host;window.orderFrontRegardless();session.attach(to:host)
        model.provider = .google; model.source="en";model.target="zh-CN";model.setPopupVisible(true)
        func wait(_ condition: ()->Bool) async -> Bool {
            for _ in 0..<300 { if condition() {return true};try? await Task.sleep(nanoseconds:10_000_000) }
            return false
        }
        func start(_ text:String) {
            model.input=text;model.translate(forceRefresh:true)
        }
        func expectPreview(_ text:String) async {
            let ok=await wait {model.previewOutput.hasSuffix(text)}
            precondition(ok && model.busy && model.output.isEmpty,"Expected preview: \(text)")
        }
        func expectFinal(_ text:String) async {
            let ok=await wait {!model.busy}
            precondition(ok && model.output.hasSuffix(text) && model.previewOutput.isEmpty,"Expected final: \(text)")
        }

        start("previous selection");await expectPreview("previous selection");await expectFinal("previous selection")
        _ = try await page.evaluateJavaScript("""
        box.addEventListener('input', () => {
          out.innerText = '译文 zh-CN: previous selection';
          spin.style.display = 'block';
          setTimeout(() => spin.style.display = 'none', 450);
          setTimeout(() => out.innerText = 'current selection', 850);
        }, {once:true});
        """)
        model.accept("current selection",origin:"fixture")
        precondition(model.previewOutput.isEmpty && model.output.isEmpty)
        let finished = await wait {
            precondition(!model.previewOutput.hasSuffix("previous selection") && !model.output.hasSuffix("previous selection"))
            return !model.busy
        }
        precondition(finished && model.output == "current selection")
        print("PASS stale result hidden throughout switch")

        start("same translation");await expectFinal("same translation")
        _ = try await page.evaluateJavaScript("""
        box.addEventListener('input', () => { out.innerText = '译文 zh-CN: same translation'; }, {once:true});
        """)
        model.accept("new selection",origin:"fixture")
        let begin=ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime-begin < 2.8 {
            precondition(model.previewOutput.isEmpty && model.output.isEmpty)
            try await Task.sleep(nanoseconds:10_000_000)
        }
        await expectFinal("new selection")
        print("PASS unchanged result triggers fresh navigation")
        start("cancel preview"); await expectPreview("cancel preview")
        model.cancel()
        try await Task.sleep(nanoseconds: 900_000_000)
        precondition(model.previewOutput.isEmpty && model.output.isEmpty && !model.busy)
        print("PASS cancellation clears preview and prevents late completion")

        start("retry preview"); await expectPreview("retry preview")
        model.translate(forceRefresh: true)
        precondition(model.previewOutput.isEmpty && model.output.isEmpty)
        await expectPreview("retry preview"); await expectFinal("retry preview")
        print("PASS retry clears preview before the fresh result")
        withExtendedLifetime(window) {}
    }
}
