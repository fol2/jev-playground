// The Jev key from the environment, else from the repository's untracked .env; never printed.
import Foundation

func typesafeKey(root: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    if let key = environment["TYPESAFE_API_KEY"]?.trimmingCharacters(in: .whitespaces), !key.isEmpty { return key }
    guard let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) else { return nil }
    var key: String?
    for line in text.split(whereSeparator: \.isNewline) {
        let entry = line.hasPrefix("export ") ? line.dropFirst(7) : line[...]
        guard let eq = entry.firstIndex(of: "="), entry[..<eq].trimmingCharacters(in: .whitespaces) == "TYPESAFE_API_KEY" else { continue }
        key = entry[entry.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    return key?.isEmpty == false ? key : nil
}
