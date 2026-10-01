import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    let session: PracticeSession

    @State private var index = 0
    @State private var results: [AnswerRecord] = []
    @State private var choice: Int? = nil        // nil = not answered yet, -1 = skipped
    @State private var hintShown = false
    @State private var questionStart = Date()
    @State private var confirmEnd = false
    @State private var finishedCode: String? = nil

    private var question: Question { session.questions[index] }
    private var isLast: Bool { index == session.questions.count - 1 }
    private var answered: Bool { choice != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let code = finishedCode {
                    ResultsView(session: session, results: results, code: code) {
                        model.session = nil
                    }
                } else {
                    questionScreen
                }
            }
            .background(Color.imcBackground)
        }
    }

    // MARK: Question screen

    private var questionScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(index + (answered ? 1 : 0)), total: Double(session.questions.count))
                        Text(topicLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .id("top")

                    MathText(question.prompt, size: 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)

                    if let diagram = question.diagram {
                        DiagramView(diagram: diagram)
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                            OptionButton(letter: String("ABCDE".map { $0 }[min(i, 4)]), markup: option,
                                         state: optionState(i)) {
                                answer(i)
                            }
                        }
                    }

                    if hintShown && !answered {
                        FeedbackCard(color: .imcAccent, title: "Hint", markup: question.hint)
                    }

                    if let c = choice {
                        feedback(for: c).id("feedback")
                    }
                }
                .padding()
                .animation(.easeOut(duration: 0.2), value: choice)
                .animation(.easeOut(duration: 0.2), value: hintShown)
            }
            .onChange(of: index) { _ in
                proxy.scrollTo("top", anchor: .top)
            }
            .onChange(of: choice) { c in
                if c != nil {
                    withAnimation { proxy.scrollTo("feedback", anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle(session.only == nil ? "Daily practice" : "Topic drill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") { confirmEnd = true }
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(results.isEmpty ? "End without saving" : "End and see results", role: .destructive) { end() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(results.isEmpty ? "You haven't answered any questions yet." : "You'll get a code for the questions you've done so far.")
        }
    }

    private var topicLine: String {
        var s = "Question \(index + 1) of \(session.questions.count)"
        if let t = model.topic(question.topic) { s += " · \(t.name)" }
        if question.stretch { s += " · stretch" }
        return s
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if answered {
                    Button(action: next) {
                        Text(isLast ? "See results" : "Next question").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            hintShown = true
                        } label: {
                            Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity)
                        }
                        .disabled(hintShown)
                        Button {
                            answer(-1)
                        } label: {
                            Label("Skip", systemImage: "forward").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .padding()
        }
        .background(.bar)
    }

    // MARK: Answering

    private func optionState(_ i: Int) -> OptionButton.Look {
        guard let c = choice else { return .idle }
        if i == question.correct { return .right }
        if i == c { return .wrong }
        return .dimmed
    }

    private func answer(_ i: Int) {
        guard choice == nil else { return }
        let mark: Mark = i < 0 ? .skipped : (i == question.correct ? .correct : .wrong)
        let secs = Int(Date().timeIntervalSince(questionStart).rounded())
        results.append(AnswerRecord(topic: question.topic, variant: question.variant, seed: question.seed,
                                    mark: mark, secs: secs, hint: hintShown,
                                    chose: i < 0 ? nil : question.options[i],
                                    ans: question.options[question.correct]))
        model.record(mark, topic: question.topic)
        switch mark {
        case .correct: Haptics.success()
        case .wrong: Haptics.error()
        case .skipped: Haptics.tap()
        }
        choice = i
    }

    @ViewBuilder
    private func feedback(for c: Int) -> some View {
        let answerLine = "The answer is \(question.options[question.correct])."
        if c == question.correct {
            FeedbackCard(color: .imcRight, title: "Correct", markup: question.explain)
        } else if c < 0 {
            FeedbackCard(color: .imcSkip, title: "Skipped", lead: answerLine, markup: question.explain)
        } else {
            FeedbackCard(color: .imcWrong, title: "Not quite", lead: answerLine, markup: question.explain)
        }
    }

    private func next() {
        if isLast {
            end()
        } else {
            index += 1
            choice = nil
            hintShown = false
            questionStart = Date()
        }
    }

    private func end() {
        if results.isEmpty {
            model.session = nil
        } else {
            finishedCode = model.finish(session, results: results)
        }
    }
}

// MARK: - Pieces

struct OptionButton: View {
    enum Look { case idle, right, wrong, dimmed }

    let letter: String
    let markup: String
    let state: Look
    let action: () -> Void

    private var tint: Color {
        switch state {
        case .right: return .imcRight
        case .wrong: return .imcWrong
        default: return .secondary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(letter)
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(state == .right || state == .wrong ? Color.white : Color.secondary)
                    .background(Circle().fill(state == .right || state == .wrong ? tint : Color.clear))
                    .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                MathText(markup, size: 21)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state == .right {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.imcRight)
                } else if state == .wrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.imcWrong)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .idle ? Color.secondary.opacity(0.25) : tint.opacity(state == .dimmed ? 0.15 : 0.9),
                              lineWidth: state == .idle ? 1 : 1.5))
            .opacity(state == .dimmed ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
    }

    private var background: Color {
        switch state {
        case .right: return Color.imcRight.opacity(0.12)
        case .wrong: return Color.imcWrong.opacity(0.12)
        default: return Color.imcCard
        }
    }
}

struct FeedbackCard: View {
    let color: Color
    let title: String
    var lead: String? = nil
    let markup: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            if let lead {
                MathText(lead, size: 19)
            }
            MathText(markup, size: 19)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
