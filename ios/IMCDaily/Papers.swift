import Foundation

// MARK: - Past paper data (papers.json on GitHub Pages)

struct Boundaries: Codable, Hashable {
    let bronze: Int
    let silver: Int
    let gold: Int
    let pink: Int
    let maclaurin: Int
}

struct PaperInfo: Codable, Identifiable, Hashable {
    let year: Int
    let pdf: String
    let solutions: String
    let answers: String          // 25 letters, the official answers
    let boundaries: Boundaries
    let note: String?

    var id: Int { year }
    var key: [Character] { Array(answers) }
}

private struct PapersFile: Codable {
    let version: Int
    let papers: [PaperInfo]
}

/// A finished attempt at a past paper.
struct PaperAttempt: Codable, Hashable, Identifiable {
    let year: Int
    let date: String
    let answers: [String]        // "A"..."E" or "" for blank
    let secs: [Int]              // time spent on each question
    let totalSecs: Int
    let score: Int

    var id: String { "\(year)-\(date)-\(totalSecs)" }
}

/// A paper being sat right now. Saved after every change so it survives the app closing.
struct ExamSession: Codable, Hashable, Identifiable {
    let year: Int
    let started: Date
    var answers: [String] = Array(repeating: "", count: 25)
    var secs: [Int] = Array(repeating: 0, count: 25)
    var current = 0

    var id: Int { year }
    static let duration: TimeInterval = 60 * 60
    var endsAt: Date { started.addingTimeInterval(Self.duration) }
}

// MARK: - Marking

enum QuestionResult { case correct, wrong, blank }

enum Marking {
    /// Official IMC rules: 5 marks for Q1-15, 6 for Q16-25.
    /// Wrong answers lose nothing on Q1-15, 1 mark on Q16-20 and 2 marks on Q21-25.
    static func value(_ n: Int, _ result: QuestionResult) -> Int {
        switch result {
        case .blank: return 0
        case .correct: return n <= 15 ? 5 : 6
        case .wrong: return n <= 15 ? 0 : (n <= 20 ? -1 : -2)
        }
    }

    static func result(_ answer: String, key: Character) -> QuestionResult {
        if answer.isEmpty { return .blank }
        return Character(answer) == key ? .correct : .wrong
    }

    static func score(_ answers: [String], paper: PaperInfo) -> Int {
        let key = paper.key
        return answers.enumerated().reduce(0) { total, item in
            total + value(item.offset + 1, result(item.element, key: key[item.offset]))
        }
    }

    static func grade(_ score: Int, _ b: Boundaries) -> String {
        if score >= b.maclaurin { return "Maclaurin Olympiad level" }
        if score >= b.pink { return "Gold, Pink Kangaroo level" }
        if score >= b.gold { return "Gold" }
        if score >= b.silver { return "Silver" }
        if score >= b.bronze { return "Bronze" }
        return "No certificate"
    }

    static func shortGrade(_ score: Int, _ b: Boundaries) -> String {
        if score >= b.maclaurin { return "Maclaurin" }
        if score >= b.gold { return "Gold" }
        if score >= b.silver { return "Silver" }
        if score >= b.bronze { return "Bronze" }
        return "None"
    }

    /// The code pasted back to Claude.
    static func code(_ attempt: PaperAttempt, paper: PaperInfo) -> String {
        let key = paper.key
        let items = attempt.answers.enumerated().map { i, a -> String in
            let r = result(a, key: key[i])
            let mark = r == .correct ? "C" : (r == .wrong ? "W" : "S")
            return "\(i + 1)\(a.isEmpty ? "-" : a):\(mark)@\(attempt.secs[i])"
        }.joined(separator: " ")
        let m = attempt.totalSecs / 60, s = attempt.totalSecs % 60
        return "IMCP \(attempt.year) \(attempt.date) ios time=\(m)m\(String(format: "%02d", s))s score=\(attempt.score)/135 (\(shortGrade(attempt.score, paper.boundaries))) | \(items)"
    }
}

// MARK: - Loading, sitting and saving papers

extension AppModel {
    private var papersCacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("papers.json")
    }

    private static func decodePapers(_ data: Data) -> [PaperInfo]? {
        guard let file = try? JSONDecoder().decode(PapersFile.self, from: data),
              !file.papers.isEmpty,
              file.papers.allSatisfy({ $0.answers.count == 25 }) else { return nil }
        return file.papers.sorted { $0.year < $1.year }
    }

    func loadLocalPapers() {
        if let data = try? Data(contentsOf: papersCacheURL), let p = Self.decodePapers(data) {
            papers = p
        } else if let url = Bundle.main.url(forResource: "papers", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let p = Self.decodePapers(data) {
            papers = p
        }
    }

    func refreshPapers() async {
        var request = URLRequest(url: Self.siteBase.appendingPathComponent("papers.json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let p = Self.decodePapers(result.0) else { return }
        try? result.0.write(to: papersCacheURL, options: .atomic)
        papers = p
    }

    func paper(_ year: Int) -> PaperInfo? { papers.first { $0.year == year } }

    func attempts(for year: Int) -> [PaperAttempt] {
        (state.paperAttempts ?? []).filter { $0.year == year }
    }

    // MARK: Question paper PDFs

    func pdfCacheURL(_ year: Int) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("papers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("IMC_\(year).pdf")
    }

    func hasPDF(_ year: Int) -> Bool {
        FileManager.default.fileExists(atPath: pdfCacheURL(year).path)
    }

    /// Downloads the question paper from UKMT. Returns false if it couldn't.
    func downloadPDF(_ paper: PaperInfo) async -> Bool {
        guard let url = URL(string: paper.pdf) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              result.0.starts(with: Array("%PDF".utf8)) else { return false }
        return (try? result.0.write(to: pdfCacheURL(paper.year), options: .atomic)) != nil
    }

    /// Copies a PDF chosen from Files into the app.
    func importPDF(_ year: Int, from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.starts(with: Array("%PDF".utf8)) else { return false }
        return (try? data.write(to: pdfCacheURL(year), options: .atomic)) != nil
    }

    // MARK: Sitting a paper

    func startExam(_ year: Int) {
        state.activeExam = ExamSession(year: year, started: Date())
        save()
    }

    func updateExam(_ exam: ExamSession) {
        state.activeExam = exam
        save()
    }

    /// Marks the paper, stores the attempt and returns it.
    func submitExam() -> PaperAttempt? {
        guard let exam = state.activeExam, let paper = paper(exam.year) else { return nil }
        let total = Int(min(Date(), exam.endsAt).timeIntervalSince(exam.started))
        let attempt = PaperAttempt(year: exam.year, date: Self.dayString(Date()), answers: exam.answers,
                                   secs: exam.secs, totalSecs: max(0, total),
                                   score: Marking.score(exam.answers, paper: paper))
        state.paperAttempts = (state.paperAttempts ?? []) + [attempt]
        state.activeExam = nil
        save()
        return attempt
    }

    func abandonExam() {
        state.activeExam = nil
        save()
    }
}
