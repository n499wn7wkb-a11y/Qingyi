import Foundation

final class MockTranslationProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var transportError: URLError?
    static var status = 200
    static var responseBody = "{}"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.transportError { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct AITranslationTests {
    static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        guard condition() else { fatalError("FAIL: \(description)") }
        print("PASS \(description)")
    }
    static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockTranslationProtocol.self]
        let session = URLSession(configuration: config)
        MockTranslationProtocol.responseBody = #"{"choices":[{"message":{"content":"你好"}}]}"#
        let translated = try await AITranslation.translate(text: "Hello & bye", source: "English", target: "中文", provider: .openAI, model: "demo", endpoint: "", key: "test-key", session: session)
        check(translated == "你好", "OpenAI response parsed")
        let open = MockTranslationProtocol.lastRequest!
        check(open.url?.absoluteString == "https://api.openai.com/v1/chat/completions", "OpenAI endpoint")
        check(open.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "API key uses authorization header")
        let body = try JSONSerialization.jsonObject(with: requestBody(open)) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        check(messages.last?["content"] == "Hello & bye" && messages.last?["role"] == "user", "Original text is sent as user content")
        MockTranslationProtocol.responseBody = #"{"candidates":[{"content":{"parts":[{"text":"你好"}]}}]}"#
        let gemini = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .gemini, model: "gemini-test", endpoint: "", key: "test-key", session: session)
        check(gemini == "你好", "Gemini response parsed")
        let gr = MockTranslationProtocol.lastRequest!
        check(gr.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent", "Gemini endpoint")
        check(gr.value(forHTTPHeaderField: "x-goog-api-key") == "test-key", "Gemini key sent in header")
        MockTranslationProtocol.responseBody = #"{"choices":[{"message":{"content":"你好"}}]}"#
        _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "deepseek-flash", endpoint: "", key: "test-key", session: session)
        let ds = MockTranslationProtocol.lastRequest!
        check(ds.url?.absoluteString == "https://api.deepseek.com/chat/completions", "DeepSeek official endpoint")
        let dsBody = try JSONSerialization.jsonObject(with: requestBody(ds)) as! [String: Any]
        check((dsBody["thinking"] as? [String: String])?["type"] == "disabled", "DeepSeek defaults to non-thinking mode")
        check((dsBody["temperature"] as? Double) == 1.3, "DeepSeek translation temperature")
        _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "deepseek-flash", endpoint: "", key: "test-key", deepSeekThinking: true, session: session)
        let thinkingBody = try JSONSerialization.jsonObject(with: requestBody(MockTranslationProtocol.lastRequest!)) as! [String: Any]
        check((thinkingBody["thinking"] as? [String: String])?["type"] == "enabled" && thinkingBody["temperature"] == nil, "DeepSeek thinking mode can be enabled")
        _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "demo", endpoint: "", key: "test-key", customInstruction: "语言自然", session: session)
        let customBody = try JSONSerialization.jsonObject(with: requestBody(MockTranslationProtocol.lastRequest!)) as! [String: Any]
        let customMessages = customBody["messages"] as! [[String: String]]
        check(customMessages.first?["content"]?.contains("语言自然") == true, "Translation preferences sent in system instruction")
        MockTranslationProtocol.responseBody = #"{"choices":[{"finish_reason":"length","message":{"content":"部分译文"}}]}"#
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("FAIL: truncated output accepted")
        } catch APIError.truncated { print("PASS truncated output reported") }
        MockTranslationProtocol.responseBody = #"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"部分译文"}]}}]}"#
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .gemini, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("FAIL: truncated Gemini output accepted")
        } catch APIError.truncated { print("PASS Gemini truncated output reported") }
        MockTranslationProtocol.responseBody = #"{"choices":[{"message":{"content":"你好"}}]}"#
        _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .custom, model: "demo", endpoint: "https://example.com/v1/", key: "test-key", session: session)
        check(MockTranslationProtocol.lastRequest?.url?.absoluteString == "https://example.com/v1/chat/completions", "Custom base URL resolves correctly")
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .custom, model: "demo", endpoint: "http://example.com/v1", key: "test-key", session: session)
            fatalError("FAIL: insecure URL accepted")
        } catch APIError.invalidURL { print("PASS insecure URL rejected") }
        MockTranslationProtocol.status = 401
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .openAI, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("FAIL: HTTP error accepted")
        } catch APIError.http(401) { print("PASS HTTP errors reported") }
        MockTranslationProtocol.status = 400
        MockTranslationProtocol.responseBody = #"{"error":{"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .gemini, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("invalid Gemini key accepted")
        } catch APIError.service(400, let hint) { check(hint.contains("API Key"), "Gemini invalid-key error classified") }
        MockTranslationProtocol.responseBody = #"{"error":{"message":"private original and secret key should never be echoed"}}"#
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .openAI, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("bad request accepted")
        } catch { check(!error.localizedDescription.contains("private original"), "Raw service errors never echoed") }
        MockTranslationProtocol.status = 200
        for reason in ["insufficient_system_resource", "abort", "unexpected_future_reason"] {
            MockTranslationProtocol.responseBody = "{\"choices\":[{\"finish_reason\":\"\(reason)\",\"message\":{\"content\":\"partial\"}}]}"
            do {
                _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "demo", endpoint: "", key: "test-key", session: session)
                fatalError("aborted output accepted")
            } catch APIError.interrupted { print("PASS abnormal completion rejected: \(reason)") }
        }
        for reason in ["end_turn", "eos", "completed", "length", "content_filter", "abort", "tool_calls", "unexpected_future_reason"] {
            MockTranslationProtocol.responseBody = #"{"choices":[{"finish_reason":"\#(reason)","message":{"content":"译文"}}]}"#
            do {
                let result = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .custom, model: "demo", endpoint: "https://example.com/v1", key: "test-key", session: session)
                check(["end_turn", "eos", "completed"].contains(reason) && result == "译文", "Custom normal ending accepted: \(reason)")
            } catch APIError.truncated { check(reason == "length", "Custom truncation rejected") }
              catch APIError.blocked { check(reason == "content_filter", "Custom filtering rejected") }
              catch APIError.interrupted { check(["abort", "tool_calls"].contains(reason), "Custom interruption rejected: \(reason)") }
              catch APIError.unsupportedFinish { check(reason == "unexpected_future_reason", "Unknown custom ending reported") }
        }
        for (status, body) in [(402, ""), (400, #"{"error":{"message":"Insufficient Balance"}}"#), (400, #"{"error":{"code":"insufficient_balance"}}"#)] {
            MockTranslationProtocol.status = status
            MockTranslationProtocol.responseBody = body
            do {
                _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .deepSeek, model: "demo", endpoint: "", key: "test-key", session: session)
                fatalError("Balance error accepted")
            } catch APIError.service(let actual, let hint) {
                check(actual == status && hint.contains("余额不足"), "DeepSeek balance error classified: \(status)")
            }
        }
        MockTranslationProtocol.status = 200
        for code in [URLError.timedOut, .notConnectedToInternet, .cannotFindHost, .secureConnectionFailed] {
            MockTranslationProtocol.transportError = URLError(code)
            do {
                _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .openAI, model: "demo", endpoint: "", key: "test-key", session: session)
                fatalError("network error accepted")
            } catch APIError.network(let actual) { check(actual == code, "Transport error mapped: \(code.rawValue)") }
        }
        MockTranslationProtocol.transportError = URLError(.cancelled)
        do {
            _ = try await AITranslation.translate(text: "Hello", source: "English", target: "中文", provider: .openAI, model: "demo", endpoint: "", key: "test-key", session: session)
            fatalError("cancelled request accepted")
        } catch is CancellationError { print("PASS cancellation preserved") }
        check(AITranslation.validEndpoint("http://example.com") == nil, "HTTP rejected by shared validator")
        check(AITranslation.validEndpoint("https://user:pass@example.com") == nil, "Credentials in URL rejected")
        check(AITranslation.validEndpoint("https://example.com?key=secret") == nil, "Query in endpoint rejected")
        check(AITranslation.privateSession.configuration.urlCache == nil && AITranslation.privateSession.configuration.httpCookieStorage == nil, "Dedicated session disables cache and cookies")
        session.invalidateAndCancel()
    }
}
