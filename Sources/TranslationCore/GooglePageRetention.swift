import Foundation

public enum GooglePageRetention: Int, CaseIterable, Identifiable {
    case untilQuit = 0, fiveMinutes = 5, tenMinutes = 10, thirtyMinutes = 30, oneHour = 60
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .untilQuit: return "直到退出轻译"
        case .fiveMinutes: return "5 分钟"
        case .tenMinutes: return "10 分钟"
        case .thirtyMinutes: return "30 分钟"
        case .oneHour: return "1 小时"
        }
    }
    public func remaining(since idleSince: Date, now: Date) -> TimeInterval? {
        guard self != .untilQuit else { return nil }
        return max(0, TimeInterval(rawValue * 60) - now.timeIntervalSince(idleSince))
    }
}
