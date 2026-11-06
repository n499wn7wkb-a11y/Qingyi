private func require(_ condition: @autoclosure () -> Bool, _ message: String = "check failed") {
    guard condition() else { fatalError(message) }
}
import Foundation
final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
@main struct Check {
 static func main() throws {
    let defaults = MemoryDefaults(suiteName: "notes-regression")!
    var calls = 0
    var duplicate = false
    var noteID = "note-1"
    let runner: ([String]) throws -> String = { args in
        calls += 1
        require(args.count == 6 && args[0] == "append")
        require(!args[4].contains("<script>"))
        duplicate = args[5] == "duplicate"
        return "\(duplicate && noteID == "note-1" ? "duplicate" : "saved")\n\(noteID)\n<body>内容</body>\n"
    }
    let saved = try NotesArchive.save(folderID: "f", original: "<script> & 中文", translation: "译文", date: "2026-11-04", defaults: defaults, runScript: runner)
    require(saved && calls == 1 && !duplicate)
    let again = try NotesArchive.save(folderID: "f", original: "<script> & 中文", translation: "译文", date: "2026-11-04", defaults: defaults, runScript: runner)
    require(!again && calls == 2 && duplicate)
    noteID = "note-2"
    let recreated = try NotesArchive.save(folderID: "f", original: "<script> & 中文", translation: "译文", date: "2026-11-04", defaults: defaults, runScript: runner)
    require(recreated && calls == 3)
    let records = try defaults.values.values.map { try JSONDecoder().decode(ArchiveRecord.self, from: $0 as! Data) }
    require(records.count == 1 && records[0].noteID == "note-2" && records[0].entries.count == 1)
    let snapshot = defaults.values.values.first as! Data
    do {
      _ = try NotesArchive.save(folderID: "f", original: "新内容", translation: "译文", date: "2026-11-04", defaults: defaults, runScript: { _ in throw NotesArchiveError.message("failed") })
      fatalError("Expected failure")
    } catch { require(defaults.values.values.first as! Data == snapshot) }
    print("PASS: one call per save, deduplication, HTML escaping, missing-note record reset, no record change on failure")
 }
}
