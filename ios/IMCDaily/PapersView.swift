import SwiftUI
import UniformTypeIdentifiers

struct PapersView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Sit a real past paper with a 60-minute timer. Answer on the sheet at the bottom, and it's marked with the official rules as soon as you finish.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Past papers") {
                    if model.papers.isEmpty {
                        Text("Papers couldn't load. Pull down to try again.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.papers) { paper in
                        NavigationLink(value: paper.year) {
                            PaperRow(paper: paper)
                        }
                    }
                }
            }
            .navigationTitle("Papers")
            .navigationDestination(for: Int.self) { year in
                PaperDetailView(year: year)
            }
            .refreshable { await model.refresh() }
        }
    }
}

private struct PaperRow: View {
    @EnvironmentObject private var model: AppModel
    let paper: PaperInfo

    var body: some View {
        let best = model.attempts(for: paper.year).max { $0.score < $1.score }
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("IMC \(String(paper.year))")
                    .font(.body.weight(.semibold))
                if let best {
                    Text("Best: \(best.score) / 135")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(paper.note ?? "Not attempted yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let best {
                GradeChip(grade: Marking.shortGrade(best.score, paper.boundaries))
            }
        }
        .padding(.vertical, 2)
    }
}

struct GradeChip: View {
    let grade: String

    private var color: Color {
        switch grade {
        case "Maclaurin", "Gold": return .imcSkip
        case "Silver": return .secondary
        case "Bronze": return .imcWrong
        default: return .secondary
        }
    }

    var body: some View {
        Text(grade)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct PaperDetailView: View {
    @EnvironmentObject private var model: AppModel
    let year: Int

    @State private var pdfReady = false
    @State private var downloading = false
    @State private var downloadFailed = false
    @State private var showImporter = false
    @State private var confirmStart = false

    var body: some View {
        Group {
            if let paper = model.paper(year) {
                content(paper)
            } else {
                Text("This paper isn't available.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("IMC \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pdfReady = model.hasPDF(year) }
    }

    private func content(_ paper: PaperInfo) -> some View {
        List {
            if let note = paper.note {
                Section { Label(note, systemImage: "info.circle").font(.subheadline) }
            }

            Section {
                if pdfReady {
                    Button {
                        confirmStart = true
                    } label: {
                        Label("Start timed paper", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else {
                    Button {
                        Task {
                            downloading = true
                            downloadFailed = false
                            pdfReady = await model.downloadPDF(paper)
                            downloadFailed = !pdfReady
                            downloading = false
                        }
                    } label: {
                        HStack {
                            Label("Download question paper", systemImage: "arrow.down.circle")
                            Spacer()
                            if downloading { ProgressView() }
                        }
                    }
                    .disabled(downloading)
                    if downloadFailed {
                        Text("Couldn't download it from UKMT. If you have the PDF saved, choose it from Files instead.")
                            .font(.footnote)
                            .foregroundStyle(Color.imcWrong)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose the PDF from Files", systemImage: "folder")
                    }
                }
            } header: {
                Text("Sit the paper")
            } footer: {
                Text("60 minutes, no calculator. Use paper for working. The timer keeps running if you leave the app.")
            }

            Section("Grade boundaries that year") {
                BoundaryRow(label: "Bronze", value: paper.boundaries.bronze)
                BoundaryRow(label: "Silver", value: paper.boundaries.silver)
                BoundaryRow(label: "Gold", value: paper.boundaries.gold)
                BoundaryRow(label: "Pink Kangaroo", value: paper.boundaries.pink)
                BoundaryRow(label: "Maclaurin Olympiad", value: paper.boundaries.maclaurin)
            }

            let attempts = model.attempts(for: year)
            if !attempts.isEmpty {
                Section("Your attempts") {
                    ForEach(attempts.reversed()) { attempt in
                        NavigationLink {
                            PaperResultView(attempt: attempt, paper: paper, done: nil)
                        } label: {
                            HStack {
                                Text(attempt.date).monospacedDigit()
                                Spacer()
                                Text("\(attempt.score) / 135").monospacedDigit().foregroundStyle(.secondary)
                                GradeChip(grade: Marking.shortGrade(attempt.score, paper.boundaries))
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Start the \(String(year)) paper?", isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Start the 60-minute timer") { model.startExam(year) }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Have paper and a pencil ready. No calculator.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                pdfReady = model.importPDF(year, from: url)
                downloadFailed = !pdfReady
            }
        }
    }
}

private struct BoundaryRow: View {
    let label: String
    let value: Int
    var body: some View {
        LabeledContent(label) {
            Text("\(value)+").monospacedDigit()
        }
    }
}
