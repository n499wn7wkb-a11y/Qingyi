private func require(_ condition: @autoclosure () -> Bool, _ message: String = "check failed") {
    guard condition() else { fatalError(message) }
}
import AppKit
import WebKit
import TranslationCore
final class FixtureScheme: NSObject, WKURLSchemeHandler {
    var loads = 0
    var urls: [URL] = []
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        loads += 1; urls.append(task.request.url!)
        let text = URLComponents(url: task.request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {$0.name == "q" || $0.name == "text"})?.value ?? ""
        let value = String(data:try! JSONSerialization.data(withJSONObject:[text]),encoding:.utf8)!
        let html = """
        <button aria-label="Text translation model">Advanced</button><textarea aria-label="Source text"></textarea><div class="xsPT1b" style="display:none"></div><div jsname="jqKxS"></div>
        <script>
        const box=document.querySelector('textarea'),out=document.querySelector('[jsname="jqKxS"]'),spinner=document.querySelector('.xsPT1b');
        box.value=\(value)[0];out.innerText=box.value ? '译文：'+box.value : '';
        window.inputs=0;
        if (location.search.includes('hydrate=1')) setTimeout(()=>{box.value='';out.innerText=''},700);
        box.addEventListener('input',()=>{window.inputs++;out.innerText='';spinner.style.display='block';setTimeout(()=>{out.innerText='译文：'+box.value;spinner.style.display='none'},150)});
        </script>
        """
        if task.request.url?.host == "error" {
            task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode:400, httpVersion:nil, headerFields:["Content-Type":"text/html"])!)
        } else {
            task.didReceive(URLResponse(url: task.request.url!, mimeType:"text/html", expectedContentLength:html.utf8.count,textEncodingName:"utf-8"))
        }
        task.didReceive(Data(html.utf8));task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
@main struct Check {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let model=AppModel(defaults: UserDefaults(suiteName: "QingyiTest-" + UUID().uuidString)!, keyReader: { _ in "" }, configuredReader: { [] });model.provider = .google
        let handler=FixtureScheme()
        var creations=0
        let session=GooglePageSession(model:model,pageFactory:{
            creations += 1
            let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.setURLSchemeHandler(handler,forURLScheme:"fixture")
            return WKWebView(frame:NSRect(x:0,y:0,width:840,height:620),configuration:config)
        })
        model.googlePageSession = session
        session.setPopupVisible(true)
        for text in ["first","second","third"] {
            model.webRequestID=UUID();model.busy=true;model.output=""
            session.translate(text:text,source:"en",target:"zh-CN",url:URL(string:"fixture://translate?q=\(text)")!,requestID:model.webRequestID)
            for _ in 0..<150 {if !model.busy {break};try await Task.sleep(nanoseconds:100_000_000)}
            require(model.output == "译文："+text,"Wrong or missing result: \(model.output), error: \(model.error ?? "none")")
        }
        require(creations==1 && handler.loads==1,"Expected one retained page and in-place updates")
        // A completed identical input should reuse the verified DOM without firing input.
        let retainedLoads = handler.loads
        model.cancel();session.setPopupVisible(false)
        model.webRequestID=UUID();model.busy=true;model.output=""
        let repeatStart=Date()
        session.translate(text:"third",source:"en",target:"zh-CN",url:URL(string:"fixture://translate?q=third")!,requestID:model.webRequestID)
        for _ in 0..<100 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
        require(model.output=="译文：third" && handler.loads==retainedLoads,"Identical input unnecessarily navigated")
        require(Date().timeIntervalSince(repeatStart)<2,"Identical input waited for three-second fallback")
        model.webRequestID=UUID();model.busy=true;model.output=""
        session.translate(text:"third",source:"en",target:"zh-CN",url:URL(string:"fixture://translate?q=third")!,requestID:model.webRequestID,forceRefresh:true)
        for _ in 0..<150 {if !model.busy {break};try await Task.sleep(nanoseconds:100_000_000)}
        require(model.output=="译文：third" && handler.loads==retainedLoads+1,"Explicit refresh did not navigate")
        let special = "A+B & C=D, 50% off.\r\n中文🙂 Café e\u{301}."
        let expected = "译文：" + special.replacingOccurrences(of:"\r\n",with:"\n")
        for _ in 0..<2 {
            model.webRequestID=UUID();model.busy=true;model.output=""
            session.translate(text:special,source:"en",target:"zh-CN",url:URL(string:"fixture://translate")!,requestID:model.webRequestID)
            for _ in 0..<150 {if !model.busy {break};try await Task.sleep(nanoseconds:100_000_000)}
            require(model.output==expected,"Unicode/CRLF input failed: \(model.error ?? "none")")
        }
        // Long text is never navigated in a URL. Delayed hydration clears the first
        // injection, so the page must confirm/retry rather than accept missing text.
        let long=String(repeating:"中文测试",count:1250)
        var parts=URLComponents(string:"fixture://translate")!
        parts.queryItems=[URLQueryItem(name:"text",value:long),URLQueryItem(name:"hydrate",value:"1")]
        model.webRequestID=UUID();model.busy=true;model.output=""
        session.translate(text:long,source:"zh-CN",target:"en",url:parts.url!,requestID:model.webRequestID)
        for _ in 0..<150 {if !model.busy {break};try await Task.sleep(nanoseconds:100_000_000)}
        require(model.output=="译文："+long,"Long input was lost or not translated: \(model.error ?? "none")")
        require(handler.urls.last!.absoluteString.utf8.count<8000 && !handler.urls.last!.absoluteString.contains("text="),"Long text remained in navigation URL")
        model.webRequestID=UUID();model.busy=true;model.output=""
        session.translate(text:"bad",source:"en",target:"zh-CN",url:URL(string:ProcessInfo.processInfo.environment["QINGYI_TEST_HTTP_URL"]!)!,requestID:model.webRequestID,forceRefresh:true)
        for _ in 0..<50 {if !model.busy {break};try await Task.sleep(nanoseconds:100_000_000)}
        require(!model.busy && model.error?.contains("HTTP 400")==true,"HTTP failure did not stop promptly: \(model.error ?? "none")")
        model.error=nil
        session.setPopupVisible(false)
        require(session.hasRetainedPage)
        model.webRequestID=UUID();model.busy=true
        session.translate(text:"cancelled",source:"en",target:"zh-CN",url:URL(string:"fixture://translate?q=cancelled")!,requestID:model.webRequestID)
        session.cancelRequest();model.output="sentinel"
        try await Task.sleep(nanoseconds:1_000_000_000)
        require(model.output=="sentinel","Cancelled result overwrote current content")
        let date=Date(timeIntervalSince1970:0)
        require(GooglePageRetention.untilQuit.remaining(since:date,now:date.addingTimeInterval(99999))==nil)
        require(GooglePageRetention.fiveMinutes.remaining(since:date,now:date.addingTimeInterval(299))==1)
        require(GooglePageRetention.fiveMinutes.remaining(since:date,now:date.addingTimeInterval(301))==0)
        try await PreviewRegression.run()
        print("PASS: real WKWebView local fixture, reuse, identical input without reload, explicit refresh, 5000-character injection with hydration reset, fast HTTP 400 failure, cancellation and retention")
    }
}
