import Foundation

public struct Language: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(_ id: String, _ name: String) { self.id = id; self.name = name }
    public static let targets: [Language] = [
        .init("zh-CN", "简体中文"), .init("zh-TW", "繁體中文"), .init("en", "English"),
        .init("ja", "日本語"), .init("ko", "한국어"), .init("fr", "Français"),
        .init("de", "Deutsch"), .init("es", "Español"), .init("it", "Italiano"),
        .init("pt", "Português"), .init("ru", "Русский"), .init("ar", "العربية")
    ]
    public static func name(for code: String) -> String {
        targets.first(where: { $0.id == code })?.name ?? (code == "zh" ? "中文" : code)
    }
}

public enum TranslationError: LocalizedError, Equatable {
    case emptyInput, tooLong
    public var errorDescription: String? {
        switch self {
        case .emptyInput: return "请先在其他应用中选中一段文字。"
        case .tooLong: return "这段文字过长，请每次选择不超过 5,000 个字符。"
        }
    }
}
