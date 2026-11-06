import Foundation
import CryptoKit

struct NotesFolder: Identifiable, Hashable {
    let id: String
    let path: String
}
struct ArchiveRecord: Codable {
    var noteID: String
    var bodyHash: String
    var entries: [String]
}
enum NotesArchiveError: LocalizedError {
    case noteMissing
    case message(String)
    var errorDescription: String? {
        switch self {
        case .noteMissing: return "当天的存档笔记不存在。"
        case .message(let message): return message
        }
    }
}
enum NotesArchive {
    static let queue = DispatchQueue(label: "com.bowen.qingyi.notes-archive", qos: .userInitiated)
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
    // Notes exports pixel sizes at two thirds of the size its HTML importer expects.
    // Restore those sizes before re-importing existing content during an append.
    static func prepareExistingHTML(_ html: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "(?i)(font-size\\s*:\\s*)([0-9]+(?:\\.[0-9]+)?)(px)")
        let source = html as NSString
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: source.length))
        let result = NSMutableString(string: html)
        for match in matches.reversed() {
            let number = source.substring(with: match.range(at: 2))
            guard let size = Double(number), size.isFinite else { continue }
            let scaled = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), size * 1.5)
            result.replaceCharacters(in: match.range(at: 2), with: scaled)
        }
        return result as String
    }
    static func run(_ arguments: [String]) throws -> String {
        guard let script = Bundle.main.url(forResource: "NotesArchive", withExtension: "scpt") ?? Bundle.main.url(forResource: "NotesArchive", withExtension: "applescript") else { throw NotesArchiveError.message("缺少备忘录组件。") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [script.path] + arguments
        let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            if detail.contains("-1743") || detail.contains("-1744") { throw NotesArchiveError.message("未获准访问备忘录。请在系统设置的隐私与安全性 → 自动化中允许轻译访问备忘录。") }
            if detail.contains("(8101)") { throw NotesArchiveError.noteMissing }
            if detail.contains("(8102)") { throw NotesArchiveError.message("保存位置不存在，请在轻译设置中重新选择备忘录文件夹。") }
            if detail.contains("8003") { throw NotesArchiveError.message("当天的存档笔记已被修改，为避免覆盖，暂时无法追加。") }
            if detail.contains("8001") || detail.contains("8002") { throw NotesArchiveError.message("存档笔记已移动或包含附件，暂时无法追加。请检查备忘录。") }
            throw NotesArchiveError.message("无法访问或保存到备忘录，请检查授权、文件夹和笔记是否存在。")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func folders() throws -> [NotesFolder] {
        try run(["folders"]).components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 ? NotesFolder(id: parts[0], path: parts[1]) : nil
        }
    }
    static func splitResult(_ result: String) throws -> (String, String) {
        guard let newline = result.firstIndex(of: "\n") else { throw NotesArchiveError.message("备忘录没有返回有效结果。") }
        // osascript adds one trailing newline when printing the returned value.
        var body = String(result[result.index(after: newline)...]); if body.hasSuffix("\n") { body.removeLast() }
        return (String(result[..<newline]), body)
    }
    static func save(folderID: String, original: String, translation: String, date: String, defaults: UserDefaults = .standard, runScript: ([String]) throws -> String = NotesArchive.run) throws -> Bool {
        let key = "notes.record." + digest(folderID + "\n" + date)
        var record = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ArchiveRecord.self, from: $0) }
        let entryHash = digest(original + "\u{0}" + translation)
        let entry = "<div>\(escape(original))</div><div>\(escape(translation))</div>"
        // One script transaction reads, checks, formats and writes the note.
        // Never pass the whole existing body between two subprocesses.
        let result = try runScript(["append", folderID, record?.noteID ?? "", "<h1>\(escape(date))</h1>", entry,
                              record?.entries.contains(entryHash) == true ? "duplicate" : "new"])
        guard let newline = result.firstIndex(of: "\n") else { throw NotesArchiveError.message("备忘录没有返回有效结果。") }
        let outcome = String(result[..<newline])
        let (id, newBody) = try splitResult(String(result[result.index(after: newline)...]))
        guard outcome == "saved" || outcome == "duplicate" else { throw NotesArchiveError.message("备忘录返回了未知状态。") }
        if outcome == "duplicate" { return false }
        if record?.noteID != id { record = ArchiveRecord(noteID: id, bodyHash: "", entries: []) }
        record!.bodyHash = digest(newBody); record!.entries.append(entryHash)
        defaults.set(try JSONEncoder().encode(record!), forKey: key)
        return true
    }
}
