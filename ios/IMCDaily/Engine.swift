import Foundation
import JavaScriptCore

// MARK: - Models shared with the JavaScript engine

struct Topic: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let status: String   // "learned", "warm" or "locked"
    let note: String
}

struct Question: Codable, Identifiable, Hashable {
    let topic: String
    let variant: String
    let seed: Int
    let prompt: String
    let options: [String]
    let correct: Int
    let hint: String
    let explain: String
    let stretch: Bool
    var diagram: Diagram? = nil

    var id: String { "\(topic).\(variant)#\(seed)" }
}

enum Mark: String, Codable {
    case correct = "C", wrong = "W", skipped = "S"
}

struct AnswerRecord: Codable, Hashable {
    let topic: String
    let variant: String
    let seed: Int
    let mark: Mark
    let secs: Int
    let hint: Bool
    let chose: String?
    let ans: String
}

struct CodeMeta: Codable {
    let date: String
    let app: String
    let mode: String
    let only: String?
    let seed: Int
    let unlocked: [String]
    let totalSecs: Int
    let planned: Int
}

// MARK: - Engine

/// Runs the question generators (engine.js, the same code as the web page)
/// in JavaScriptCore. No web view is involved.
final class QuestionEngine {
    let version: Int
    let topics: [Topic]
    private let context: JSContext
    private let api: JSValue

    /// Returns nil if the script fails to load or does not expose the expected API.
    init?(source: String) {
        guard let context = JSContext() else { return nil }
        var failed = false
        context.exceptionHandler = { _, _ in failed = true }
        context.evaluateScript(source)
        guard !failed,
              let api = context.objectForKeyedSubscript("IMC"),
              !api.isUndefined, !api.isNull,
              let version = api.objectForKeyedSubscript("version")?.toNumber()?.intValue,
              let topicsJSON = api.invokeMethod("topics", withArguments: [])?.toString(),
              let data = topicsJSON.data(using: .utf8),
              let topics = try? JSONDecoder().decode([Topic].self, from: data),
              !topics.isEmpty
        else { return nil }

        self.context = context
        self.api = api
        self.version = version
        self.topics = topics

        // Smoke test: make sure a session can actually be planned.
        if plan(seed: 123456, stats: [:], size: 4, only: nil, unlocked: []).isEmpty { return nil }
    }

    func plan(seed: Int, stats: [String: TopicStat], size: Int, only: String?, unlocked: [String]) -> [Question] {
        let statsJSON = Self.json(stats) ?? "{}"
        let unlockedJSON = Self.json(unlocked) ?? "[]"
        let onlyArg: Any = only ?? NSNull()
        guard let out = api.invokeMethod("plan", withArguments: [seed, statsJSON, size, onlyArg, unlockedJSON])?.toString(),
              let data = out.data(using: .utf8),
              let questions = try? JSONDecoder().decode([Question].self, from: data)
        else { return [] }
        return questions
    }

    /// Returns the topic id the password unlocks, or nil.
    func checkPassword(_ word: String) -> String? {
        guard let id = api.invokeMethod("checkPassword", withArguments: [word])?.toString(),
              !id.isEmpty, id != "undefined", id != "null" else { return nil }
        return id
    }

    func sessionCode(meta: CodeMeta, results: [AnswerRecord]) -> String {
        guard let m = Self.json(meta), let r = Self.json(results),
              let code = api.invokeMethod("code", withArguments: [m, r])?.toString()
        else { return "" }
        return code
    }

    private static func json<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
