import SwiftUI
import PDFKit

/// Decides whether to show the paper being sat or its results.
struct ExamContainer: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            if let attempt = model.examResult, let paper = model.paper(attempt.year) {
                PaperResultView(attempt: attempt, paper: paper) { model.examResult = nil }
            } else if let exam = model.state.activeExam, let paper = model.paper(exam.year) {
                ExamView(exam: exam, paper: paper)
            } else {
                ProgressView()
            }
        }
    }
}

struct ExamView: View {
    @EnvironmentObject private var model: AppModel
    let paper: PaperInfo
    @State private var exam: ExamSession
    @State private var now = Date()
    @State private var confirmSubmit = false
    @State private var confirmQuit = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(exam: ExamSession, paper: PaperInfo) {
        self.paper = paper
        _exam = State(initialValue: exam)
    }

    private var remaining: Int { max(0, Int(exam.endsAt.timeIntervalSince(now).rounded(.up))) }
    private var blanks: Int { exam.answers.filter(\.isEmpty).count }

    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(url: model.pdfCacheURL(exam.year))
            Divider()
            answerPanel
                .padding(.vertical, 12)
                .background(.bar)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Quit", role: .destructive) { confirmQuit = true }
            }
            ToolbarItem(placement: .principal) {
                Label(timeString(remaining), systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remaining < 300 ? Color.imcWrong : Color.primary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") { confirmSubmit = true }.bold()
            }
        }
        .interactiveDismissDisabled()
        .onReceive(tick) { date in
            now = date
            if remaining == 0 {
                submit()
            } else {
                exam.secs[exam.current] += 1
                model.updateExam(exam)
            }
        }
        .confirmationDialog("Submit your answers?", isPresented: $confirmSubmit, titleVisibility: .visible) {
            Button("Submit and mark") { submit() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(blanks == 0 ? "You've answered every question." : "You've left \(blanks) blank. Blanks score 0 but never lose marks.")
        }
        .confirmationDialog("Quit this paper?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit without marking", role: .destructive) { model.abandonExam() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your answers won't be saved.")
        }
    }

    // MARK: Answer sheet

    private var answerPanel: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<25, id: \.self) { i in
                            Button { exam.current = i } label: { bubble(i) }
                                .buttonStyle(.plain)
                                .id(i)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: exam.current) { c in
                    withAnimation { proxy.scrollTo(c, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(exam.current, anchor: .center) }
            }

            HStack {
                Text("Question \(exam.current + 1)")
                    .font(.headline)
                Text(markInfo(exam.current + 1))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(exam.current == 0)
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(exam.current == 24)
            }
            .padding(.horizontal)

            HStack(spacing: 8) {
                ForEach(["A", "B", "C", "D", "E"], id: \.self) { letter in
                    let chosen = exam.answers[exam.current] == letter
                    Button { choose(letter) } label: {
                        Text(letter)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(chosen ? Color.white : Color.primary)
                            .background(chosen ? Color.imcAccent : Color.imcCard,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(chosen ? 0 : 0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Text(exam.answers[exam.current].isEmpty
                 ? "Tap a letter to answer. Leave it blank if you can't do it."
                 : "Tap \(exam.answers[exam.current]) again to clear your answer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bubble(_ i: Int) -> some View {
        let answer = exam.answers[i]
        let isCurrent = i == exam.current
        return VStack(spacing: 1) {
            Text("\(i + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(answer.isEmpty ? "–" : answer)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(answer.isEmpty ? Color.secondary : Color.imcAccent)
        }
        .frame(width: 38, height: 46)
        .background(answer.isEmpty ? Color.clear : Color.imcAccent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isCurrent ? Color.imcAccent : Color.secondary.opacity(0.25), lineWidth: isCurrent ? 2 : 1))
    }

    private func markInfo(_ n: Int) -> String {
        if n <= 15 { return "5 marks · no penalty" }
        if n <= 20 { return "6 marks · −1 if wrong" }
        return "6 marks · −2 if wrong"
    }

    private func choose(_ letter: String) {
        Haptics.tap()
        let i = exam.current
        if exam.answers[i] == letter {
            exam.answers[i] = ""
        } else {
            exam.answers[i] = letter
            if i < 24 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if exam.current == i { exam.current = i + 1 }
                }
            }
        }
        model.updateExam(exam)
    }

    private func move(_ d: Int) {
        exam.current = min(24, max(0, exam.current + d))
    }

    private func submit() {
        model.updateExam(exam)
        if let attempt = model.submitExam() {
            Haptics.success()
            model.examResult = attempt
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

// MARK: - Results

struct PaperResultView: View {
    let attempt: PaperAttempt
    let paper: PaperInfo
    let done: (() -> Void)?

    private var key: [Character] { paper.key }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    SectionLabel("IMC \(String(paper.year)) · \(attempt.date)")
                    Text("\(attempt.score) / 135")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(Marking.grade(attempt.score, paper.boundaries))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.imcAccent)
                    Text("Time: \(attempt.totalSecs / 60) min \(attempt.totalSecs % 60) s")
                        .foregroundStyle(.secondary)
                    boundaries
                }

                Card {
                    SectionLabel("Your code for Claude")
                    let code = Marking.code(attempt, paper: paper)
                    CodeBox(code: code)
                    CopyButton(text: code, prominent: true)
                }

                Card {
                    SectionLabel("Question by question")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(0..<25, id: \.self) { i in cell(i) }
                    }
                    Text("Green: right. Red: wrong (the correct letter is shown). Grey: blank.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: paper.solutions) {
                        Link(destination: url) {
                            Label("Official worked solutions", systemImage: "book")
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.imcBackground)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
    }

    private var boundaries: some View {
        let b = paper.boundaries
        let rows: [(String, Int)] = [("Bronze", b.bronze), ("Silver", b.silver), ("Gold", b.gold),
                                     ("Pink Kangaroo", b.pink), ("Maclaurin", b.maclaurin)]
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let (name, value) = row
                HStack {
                    Image(systemName: attempt.score >= value ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(attempt.score >= value ? Color.imcRight : Color.secondary)
                    Text(name)
                    Spacer()
                    Text(attempt.score >= value ? "\(value)+" : "\(value - attempt.score) more needed")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 4)
    }

    private func cell(_ i: Int) -> some View {
        let answer = attempt.answers[i]
        let result = Marking.result(answer, key: key[i])
        let points = Marking.value(i + 1, result)
        let color: Color = result == .correct ? .imcRight : (result == .wrong ? .imcWrong : .secondary)
        return VStack(spacing: 2) {
            Text("\(i + 1)").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(answer.isEmpty ? "–" : answer).font(.headline)
                if result == .wrong {
                    Text("→\(String(key[i]))").font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(color)
            Text(points > 0 ? "+\(points)" : "\(points)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
