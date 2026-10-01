import Foundation
import SwiftUI

struct TopicStat: Codable, Hashable {
    var c = 0
    var w = 0
    var s = 0
    var total: Int { c + w + s }
}

/// Everything saved on the phone.
struct SavedState: Codable {
    var streak = 0
    var lastDone: String? = nil          // yyyy-MM-dd of the last completed daily set
    var stats: [String: TopicStat] = [:]
    var unlocked: [String] = []
    var lastCode: String? = nil
    var paperAttempts: [PaperAttempt]? = nil   // optional so older saved data still loads
    var activeExam: ExamSession? = nil
}

struct PracticeSession: Identifiable {
    let id = UUID()
    let seed: Int
    let only: String?
    let questions: [Question]
    let started = Date()
    var mode: String { only == nil ? "daily" : "drill" }
}

@MainActor
final class AppModel: ObservableObject {
    static let siteBase = URL(string: "https://lewiscodeswebsites.github.io/imc-revision/")!
    static let imcDay = "2027-01-27"

    @Published private(set) var engine: QuestionEngine?
    @Published private(set) var engineSource = "Built-in questions"
    @Published var state: SavedState
    @Published var session: PracticeSession?
    @Published var papers: [PaperInfo] = []
    @Published var examResult: PaperAttempt?
    @Published private(set) var lastRefresh: Date?

    private let stateKey = "imcDaily.state.v1"
    private var refreshing = false

    init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = saved
        } else {
            state = SavedState()
        }
        loadLocalEngine()
        loadLocalPapers()
    }

    // MARK: Engine loading

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engine.js")
    }

    private func loadLocalEngine() {
        let bundled = Bundle.main.url(forResource: "engine", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap(QuestionEngine.init(source:))
        let cached = (try? String(contentsOf: cacheURL, encoding: .utf8))
            .flatMap(QuestionEngine.init(source:))

        // Use whichever is newer.
        if let cached, cached.version >= (bundled?.version ?? 0) {
            engine = cached
            engineSource = "Downloaded questions (v\(cached.version))"
        } else if let bundled {
            engine = bundled
            engineSource = "Built-in questions (v\(bundled.version))"
        }
    }

    /// Downloads the latest engine.js from GitHub Pages. Safe to call often.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await refreshPapers()

        var request = URLRequest(url: Self.siteBase.appendingPathComponent("engine.js"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let source = String(data: result.0, encoding: .utf8),
              let fresh = QuestionEngine(source: source)
        else { return }

        try? result.0.write(to: cacheURL, options: .atomic)
        lastRefresh = Date()
        // Never swap the engine in the middle of a session.
        if session == nil {
            engine = fresh
            engineSource = "Downloaded questions (v\(fresh.version))"
        }
    }

    // MARK: Topics

    var topics: [Topic] { engine?.topics ?? [] }

    func isOpen(_ topic: Topic) -> Bool {
        topic.status != "locked" || state.unlocked.contains(topic.id)
    }

    func topic(_ id: String) -> Topic? { topics.first { $0.id == id } }

    var groups: [String] {
        var seen: [String] = []
        for t in topics where !seen.contains(t.group) { seen.append(t.group) }
        return seen
    }

    enum UnlockResult { case unlocked(Topic), already(Topic), noMatch }

    func unlock(password: String) -> UnlockResult {
        guard let id = engine?.checkPassword(password), let t = topic(id) else { return .noMatch }
        if state.unlocked.contains(id) { return .already(t) }
        state.unlocked.append(id)
        save()
        return .unlocked(t)
    }

    // MARK: Sessions

    func startSession(only: String? = nil) {
        guard let engine else { return }
        let seed = Int.random(in: 100_000...999_999)
        let questions = engine.plan(seed: seed, stats: state.stats, size: only == nil ? 8 : 6,
                                    only: only, unlocked: state.unlocked)
        guard !questions.isEmpty else { return }
        session = PracticeSession(seed: seed, only: only, questions: questions)
    }

    func record(_ mark: Mark, topic: String) {
        var s = state.stats[topic] ?? TopicStat()
        switch mark {
        case .correct: s.c += 1
        case .wrong: s.w += 1
        case .skipped: s.s += 1
        }
        state.stats[topic] = s
        save()
    }

    /// Called when a session ends. Updates the streak and returns the code for Claude.
    func finish(_ session: PracticeSession, results: [AnswerRecord]) -> String {
        let today = Self.dayString(Date())
        if session.only == nil, results.count == session.questions.count, state.lastDone != today {
            if let last = state.lastDone, Self.dayDiff(last, today) == 1 {
                state.streak += 1
            } else {
                state.streak = 1
            }
            state.lastDone = today
        }
        let meta = CodeMeta(date: today, app: "ios", mode: session.mode, only: session.only, seed: session.seed,
                            unlocked: state.unlocked, totalSecs: Int(Date().timeIntervalSince(session.started)),
                            planned: session.questions.count)
        let code = engine?.sessionCode(meta: meta, results: results) ?? ""
        state.lastCode = code
        save()
        return code
    }

    // MARK: Streak and dates

    var doneToday: Bool { state.lastDone == Self.dayString(Date()) }

    var currentStreak: Int {
        guard let last = state.lastDone else { return 0 }
        return Self.dayDiff(last, Self.dayString(Date())) <= 1 ? state.streak : 0
    }

    var daysToIMC: Int { max(0, Self.dayDiff(Self.dayString(Date()), Self.imcDay)) }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func dayDiff(_ a: String, _ b: String) -> Int {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let da = f.date(from: a), let db = f.date(from: b) else { return 0 }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}
