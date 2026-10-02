import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(value: model.currentStreak, label: "Day streak", systemImage: "flame.fill")
                        StatTile(value: model.daysToIMC, label: "Days to IMC", systemImage: "calendar")
                    }

                    if model.engine == nil {
                        Card {
                            Label("Questions couldn't load", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text("Connect to the internet and pull down to try again.")
                                .foregroundStyle(.secondary)
                        }
                    } else if model.doneToday {
                        doneCard
                    } else {
                        todayCard
                    }

                    if model.engine != nil {
                        endlessCard
                        drillCard
                    }

                    Text("Challenge day: Wednesday 27 January 2027. No calculator. Work on paper.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Color.imcBackground)
            .navigationTitle("IMC Daily")
            .refreshable { await model.refresh() }
        }
    }

    private var todayCard: some View {
        Card {
            SectionLabel("Today")
            Text("Daily practice: 8 questions")
                .font(.title2.weight(.bold))
            Text("About 10 minutes. Half on techniques you've learned, half warm-ups. Skip anything you can't start, like in the real IMC.")
                .foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                model.startSession()
            } label: {
                Text("Start today's practice").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var doneCard: some View {
        Card {
            SectionLabel("Done for today")
            Text("Nice work. Streak kept.")
                .font(.title2.weight(.bold))
            if let code = model.state.lastCode, !code.isEmpty {
                Text("Your last code, if you still need to send it to Claude:")
                    .foregroundStyle(.secondary)
                CodeBox(code: code)
                CopyButton(text: code, prominent: true)
            }
            Button {
                model.startSession()
            } label: {
                Text("Do another set").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var endlessCard: some View {
        Card {
            SectionLabel("Endless")
            Text("Mixed questions until you press End. Eight or more counts for your streak.")
                .foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                model.startEndless()
            } label: {
                Label("Start endless", systemImage: "infinity")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var drillCard: some View {
        Card {
            SectionLabel("Drill one topic")
            Text("Six questions on a single technique.")
                .foregroundStyle(.secondary)
            Menu {
                ForEach(model.groups, id: \.self) { group in
                    let open = model.topics.filter { $0.group == group && model.isOpen($0) }
                    if !open.isEmpty {
                        Section(group) {
                            ForEach(open) { topic in
                                Button(topic.name) { model.startSession(only: topic.id) }
                            }
                        }
                    }
                }
            } label: {
                Label("Choose a topic", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.imcAccent)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.imcCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
