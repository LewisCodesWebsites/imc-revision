import SwiftUI

struct TopicsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(unlock)
                        Button("Unlock", action: unlock)
                            .buttonStyle(.borderedProminent)
                            .disabled(password.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(messageIsError ? Color.imcWrong : Color.imcRight)
                    }
                } header: {
                    Text("Unlock a topic")
                } footer: {
                    Text("When you learn a new technique with Claude, you get a password for it.")
                }

                ForEach(model.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(model.topics.filter { $0.group == group }) { topic in
                            TopicRow(topic: topic)
                        }
                    }
                }

                Section {
                    LabeledContent("Questions", value: model.engineSource)
                    if let date = model.lastRefresh {
                        LabeledContent("Last update check", value: date.formatted(date: .omitted, time: .shortened))
                    }
                } footer: {
                    Text("Tap an open topic to drill it. Pull down to check for new topics.")
                }
            }
            .navigationTitle("Topics")
            .refreshable { await model.refresh() }
        }
    }

    private func unlock() {
        let word = password.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        switch model.unlock(password: word) {
        case .unlocked(let topic):
            Haptics.success()
            message = "Unlocked \(topic.name). It will now appear in your daily practice."
            messageIsError = false
            password = ""
        case .already(let topic):
            message = "\(topic.name) is already unlocked."
            messageIsError = false
            password = ""
        case .noMatch:
            Haptics.error()
            message = "That password doesn't match any topic. Check the spelling."
            messageIsError = true
        }
    }
}

private struct TopicRow: View {
    @EnvironmentObject private var model: AppModel
    let topic: Topic

    var body: some View {
        let open = model.isOpen(topic)
        let stat = model.state.stats[topic.id]
        Button {
            if open { model.startSession(only: topic.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(topic.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(open ? Color.primary : Color.secondary)
                    Spacer()
                    StatusChip(topic: topic, open: open)
                }
                Text(topic.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let stat, stat.total > 0 {
                    Text("\(stat.c) of \(stat.total) right so far")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(!open)
    }
}

private struct StatusChip: View {
    let topic: Topic
    let open: Bool

    private var text: String {
        if topic.status == "warm" { return "Warm-up" }
        return open ? "Learned" : "Locked"
    }

    private var color: Color {
        if topic.status == "warm" { return .imcRight }
        return open ? .imcAccent : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            if !open { Image(systemName: "lock.fill").font(.caption2) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}
