import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var model: AppModel
    let session: PracticeSession
    let results: [AnswerRecord]
    let code: String
    let done: () -> Void

    private func count(_ m: Mark) -> Int { results.filter { $0.mark == m }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    SectionLabel(session.only == nil ? "Daily practice finished" : "Topic drill finished")
                    Text("\(count(.correct)) / \(results.count)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    HStack(spacing: 18) {
                        Tally(value: count(.correct), label: "right", color: .imcRight)
                        Tally(value: count(.wrong), label: "wrong", color: .imcWrong)
                        Tally(value: count(.skipped), label: "skipped", color: .imcSkip)
                    }
                }

                Card {
                    SectionLabel("Your code for Claude")
                    CodeBox(code: code)
                    CopyButton(text: code, prominent: true)
                    Text("Paste this into your chat with Claude so it can plan what to work on next.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Card {
                    SectionLabel("Question by question")
                    ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                        HStack {
                            Image(systemName: icon(r.mark))
                                .foregroundStyle(color(r.mark))
                            Text("\(i + 1). \(model.topic(r.topic)?.name ?? r.topic)")
                            if r.hint {
                                Text("hint").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(r.secs)s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        if i < results.count - 1 { Divider() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done)
            }
        }
    }

    private func icon(_ m: Mark) -> String {
        switch m {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private func color(_ m: Mark) -> Color {
        switch m {
        case .correct: return .imcRight
        case .wrong: return .imcWrong
        case .skipped: return .imcSkip
        }
    }
}

private struct Tally: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)").font(.headline).foregroundStyle(color).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
    }
}
