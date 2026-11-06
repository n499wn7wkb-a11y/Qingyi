import AppKit
import SwiftUI
import TranslationCore
import NaturalLanguage

@MainActor final class AppModel: ObservableObject {
    @Published var googlePageRetention: GooglePageRetention = .untilQuit {
        didSet {
            defaults.set(googlePageRetention.rawValue, forKey: "google.pageRetention")
            googlePageSession.retentionChanged()
        }
    }
    private let defaults: UserDefaults
    @Published private(set) var keyLoading = false
    private var keyReadFailed = false
    private(set) var popupVisible = false
    func setPopupVisible(_ visible: Bool) {
        popupVisible = visible
        googlePageSession.setPopupVisible(visible)
    }
    private let keyReader: (TranslationProvider) async throws -> String
    private let configuredReader: () async -> Set<TranslationProvider>
    private var configured: Set<TranslationProvider> = []
    private var keyLoadID = UUID()
    private var configuredOverrides: Set<TranslationProvider> = []
    lazy var googlePageSession = GooglePageSession(model: self)
    @Published var input = "" { didSet { if input != oldValue { invalidate() } } }
    @Published var output = ""
    @Published var previewOutput = ""
    @Published var source: String { didSet { defaults.set(source, forKey: "source"); if source != oldValue { invalidate(); if popupVisible && !input.isEmpty { translate() } } } }
    @Published var target: String { didSet { defaults.set(target, forKey: "target"); if target != oldValue { invalidate(); if popupVisible && !input.isEmpty { translate() } } } }
    @Published var busy = false
    @Published var error: String?
    @Published var detectedSource: String?
    @Published var hotkeyWarning: String?
    @Published var origin = "手动输入"
    @Published private(set) var shortcut: SelectionShortcut
    @Published var recordingShortcut = false {
        didSet { if recordingShortcut != oldValue { shortcutRecordingChanged?(recordingShortcut) } }
    }
    var registerShortcut: ((SelectionShortcut) -> String?)?
    var shortcutRecordingChanged: ((Bool) -> Void)?
    func applyShortcut(_ candidate: SelectionShortcut) -> Bool {
        if let message = candidate.validationError { hotkeyWarning = message; return false }
        guard let registerShortcut else { hotkeyWarning = "快捷键服务尚未准备好。"; return false }
        if let message = registerShortcut(candidate) { hotkeyWarning = message; return false }
        shortcut = candidate
        if let data = try? JSONEncoder().encode(candidate) { defaults.set(data, forKey: "customShortcut") }
        hotkeyWarning = nil; shortcutChanged?(); return true
    }
    var providerMenuPresented = false
    @Published var provider: TranslationProvider {
        didSet { defaults.set(provider.rawValue, forKey: "provider"); if provider != oldValue { invalidate(); webURL = nil } }
    }
    @Published var modelName: String = ""
    @Published var endpoint: String = ""
    @Published var apiKey: String = ""
    @Published var connectionMessage: String?
    @Published var testingConnection = false
    @Published var deepSeekThinking: Bool { didSet { defaults.set(deepSeekThinking, forKey: "deepSeekThinking") } }
    @Published var translationPreferences: String { didSet { defaults.set(translationPreferences, forKey: "translationPreferences") } }
    @Published var notesEnabled: Bool { didSet { defaults.set(notesEnabled, forKey: "notes.enabled") } }
    @Published var notesFolderID: String { didSet { defaults.set(notesFolderID, forKey: "notes.folderID") } }
    @Published var notesFolderPath: String { didSet { defaults.set(notesFolderPath, forKey: "notes.folderPath") } }
    @Published var notesFolders: [NotesFolder] = []
    @Published var notesLoading = false
    @Published var notesMessage: String?
    @Published var archiveBusy = false
    @Published var archiveMessage: String?
    @Published private(set) var savedArchiveKeys: Set<String> = []
    private var archiveSession = UUID()
    private var archiveStatusTask: Task<Void, Never>?
    private func archiveDate() -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    private var archiveKey: String {
        NotesArchive.digest(notesFolderID + "\u{0}" + archiveDate() + "\u{0}" + input + "\u{0}" + output)
    }
    var archiveSaved: Bool { !input.isEmpty && !output.isEmpty && savedArchiveKeys.contains(archiveKey) }
    func beginArchiveSession() {
        archiveStatusTask?.cancel(); archiveStatusTask = nil
        archiveSession = UUID(); savedArchiveKeys.removeAll(); archiveBusy = false; archiveMessage = nil
    }
    var shortcutChanged: (() -> Void)?
    var showSettings: (() -> Void)?
    @Published var webURL: URL?
    @Published var webRequestID = UUID()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(defaults: UserDefaults = .standard, keyReader: @escaping (TranslationProvider) async throws -> String = APIKeyStore.readAsync,
         configuredReader: @escaping () async -> Set<TranslationProvider> = APIKeyStore.configuredProviders) {
        self.defaults = defaults; self.keyReader = keyReader; self.configuredReader = configuredReader
        googlePageRetention = GooglePageRetention(rawValue: defaults.integer(forKey: "google.pageRetention")) ?? .untilQuit
        let savedSource = defaults.string(forKey: "source") ?? "en"
        source = savedSource == "auto" || Language.targets.contains(where: { $0.id == savedSource }) ? savedSource : "en"
        let saved = defaults.string(forKey: "target") ?? "zh-CN"
        target = Language.targets.contains(where: { $0.id == saved }) ? saved : "zh-CN"
        shortcut = SelectionShortcut.load(from: defaults)
        provider = TranslationProvider(rawValue: defaults.string(forKey: "provider") ?? "google") ?? .google
        deepSeekThinking = defaults.bool(forKey: "deepSeekThinking")
        translationPreferences = defaults.string(forKey: "translationPreferences") ?? ""
        notesEnabled = defaults.bool(forKey: "notes.enabled")
        notesFolderID = defaults.string(forKey: "notes.folderID") ?? ""
        notesFolderPath = defaults.string(forKey: "notes.folderPath") ?? ""
        loadProviderSettings()
        Task {
            let result = await configuredReader()
            configured.formUnion(result.subtracting(configuredOverrides)); refreshAvailableProviders()
        }
    }
    @Published private(set) var availableProviders: [TranslationProvider] = [.google]
    func refreshAvailableProviders() {
        availableProviders = TranslationProvider.allCases.filter { candidate in
            if candidate == .google { return true }
            guard configured.contains(candidate) else { return false }
            return candidate != .custom || AITranslation.validEndpoint(defaults.string(forKey: "endpoint.custom") ?? "") != nil
        }
    }
    func loadProviderSettings() {
        modelName = defaults.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModel
        endpoint = defaults.string(forKey: "endpoint.custom") ?? ""
        apiKey = ""; connectionMessage = nil; keyLoading = false; keyReadFailed = false
        keyLoadID = UUID()
        guard provider != .google else { return }
        let selected = provider, id = keyLoadID
        keyLoading = true
        Task {
            do {
                let key = try await keyReader(selected)
                guard provider == selected, keyLoadID == id else { return }
                keyLoading = false
                if apiKey.isEmpty { apiKey = key }
            } catch {
                guard provider == selected, keyLoadID == id else { return }
                keyLoading = false; keyReadFailed = true; connectionMessage = error.localizedDescription
            }
        }
    }
    func saveProviderSettings() -> Bool {
        guard !keyLoading else { connectionMessage = "正在读取 API Key，请稍候。"; return false }
        guard !keyReadFailed || !apiKey.isEmpty else { connectionMessage = "API Key 未能读取。请重新选择服务授权读取，或输入新密钥。"; return false }
        if provider == .custom, AITranslation.validEndpoint(endpoint) == nil {
            connectionMessage = APIError.invalidURL.localizedDescription; return false
        }
        defaults.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model.\(provider.rawValue)")
        if provider == .custom { defaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "endpoint.custom") }
        do {
            if provider != .google { try APIKeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), provider: provider) }
            keyLoadID = UUID(); keyReadFailed = false; configuredOverrides.insert(provider)
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { configured.insert(provider) }
            else { configured.remove(provider) }
            refreshAvailableProviders()
            connectionMessage = "设置已保存"; return true
        } catch { connectionMessage = error.localizedDescription; return false }
    }
    func testConnection() {
        guard provider != .google, saveProviderSettings() else { return }
        let selected = provider, model = modelName, address = endpoint, key = apiKey, thinking = deepSeekThinking
        testingConnection = true; connectionMessage = "正在测试…"
        Task {
            do {
                _ = try await AITranslation.translate(text: "Hello.", source: "English", target: "简体中文", provider: selected, model: model, endpoint: address, key: key, deepSeekThinking: thinking)
                if provider == selected { connectionMessage = "连接成功" }
            } catch { if provider == selected { connectionMessage = error.localizedDescription } }
            testingConnection = false
        }
    }
    private func invalidate() {
        generation = UUID(); webRequestID = UUID(); task?.cancel(); task = nil
        googlePageSession.cancelRequest()
        busy = false; output = ""; previewOutput = ""; error = nil; detectedSource = nil
    }
    func translate(forceRefresh: Bool = false) {
        invalidate(); webURL = nil
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = TranslationError.emptyInput.localizedDescription; return }
        guard input.unicodeScalars.count <= 5_000 else { error = TranslationError.tooLong.localizedDescription; return }
        if provider != .google {
            let id = generation, text = input, selected = provider, model = modelName, address = endpoint, thinking = deepSeekThinking, preferences = translationPreferences
            let from = source == "auto" ? "the detected language" : Language.name(for: source)
            let to = Language.name(for: target)
            busy = true
            task = Task {
                do {
                    let key = try await keyReader(selected)
                    try Task.checkCancellation()
                    guard id == generation else { return }
                    let result = try await AITranslation.translate(text: text, source: from, target: to, provider: selected, model: model, endpoint: address, key: key, deepSeekThinking: thinking, customInstruction: preferences)
                    guard !Task.isCancelled, id == generation else { return }
                    output = result; busy = false
                } catch {
                    guard !Task.isCancelled, id == generation else { return }
                    self.error = error.localizedDescription; busy = false
                }
            }
            return
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var parts = URLComponents(string: "https://translate.google.com/")!
        let googleSource: String
        if source == "auto", let recognized = NLLanguageRecognizer.dominantLanguage(for: input)?.rawValue {
            googleSource = recognized == "zh-Hans" ? "zh-CN" : (recognized == "zh-Hant" ? "zh-TW" : recognized)
            detectedSource = googleSource
        } else { googleSource = source }
        parts.percentEncodedQuery = "sl=\(encode(googleSource))&tl=\(encode(target))&text=\(encode(input))&op=translate&hl=en"
        guard let url = parts.url else { error = "无法打开翻译页面，请缩短选中的文字。"; return }
        busy = true; webURL = url; webRequestID = UUID()
        googlePageSession.translate(text: input, source: googleSource, target: target, url: url, requestID: webRequestID, forceRefresh: forceRefresh)
    }
    func cancel() { invalidate(); webURL = nil }
    func loadNotesFolders() {
        notesLoading = true; notesMessage = nil
        NotesArchive.queue.async {
            let result = Result { try NotesArchive.folders() }
            Task { @MainActor in
                self.notesLoading = false
                switch result {
                case .success(let folders): self.notesFolders = folders; if folders.isEmpty { self.notesMessage = "没有找到可用的备忘录文件夹。" }
                case .failure(let error): self.notesMessage = error.localizedDescription
                }
            }
        }
    }
    private func brieflyShowArchiveStatus(_ message: String) {
        archiveStatusTask?.cancel()
        archiveMessage = message
        let session = archiveSession
        archiveStatusTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard self.archiveSession == session else { return }
            self.archiveMessage = nil
        }
    }
    func archiveTranslation() {
        guard !archiveBusy, !input.isEmpty, !output.isEmpty else { return }
        guard !notesFolderID.isEmpty else { archiveMessage = "请先在设置中选择存储位置"; return }
        let folder = notesFolderID, original = input, translated = output
        if archiveSaved { brieflyShowArchiveStatus("已保存"); return }
        let date = archiveDate(), key = archiveKey, session = archiveSession
        archiveStatusTask?.cancel(); archiveStatusTask = nil
        archiveBusy = true; archiveMessage = nil
        NotesArchive.queue.async {
            let result = Result { try NotesArchive.save(folderID: folder, original: original, translation: translated, date: date) }
            Task { @MainActor in
                guard self.archiveSession == session else { return }
                self.archiveBusy = false
                switch result {
                case .success:
                    self.savedArchiveKeys.insert(key)
                    if self.archiveKey == key { self.brieflyShowArchiveStatus("已保存") }
                case .failure where self.archiveKey != key: break
                case .failure(let error):
                    self.brieflyShowArchiveStatus("存档失败")
                    let alert = NSAlert(); alert.messageText = "无法存档到备忘录"; alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "好"); alert.runModal()
                }

            }
        }
    }
    func switchProvider(_ selected: TranslationProvider) {
        let retry = selected == provider
        if selected != provider {
            provider = selected
            loadProviderSettings()
        }
        if popupVisible && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { translate(forceRefresh: retry) }
    }
    func clear() { invalidate(); input = ""; origin = "手动输入" }
    func accept(_ text: String, origin: String) { input = text; self.origin = origin; translate() }
}
