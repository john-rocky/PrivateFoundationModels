import PrivateFoundationModels
import PrivateFoundationModelsCoreML
import SwiftUI

/// Single-file SwiftUI demo that talks to PrivateFoundationModels exactly the
/// same way an Apple FoundationModels chat app would. Drop `PFMChatApp.swift`
/// into a fresh iOS 18+ Xcode project, add the package, run.
@main
struct PFMChatApp: App {
    @StateObject private var loader = ModelLoader()

    var body: some Scene {
        WindowGroup {
            ChatView(loader: loader)
        }
    }
}

@MainActor
final class ModelLoader: ObservableObject {
    enum Status {
        case idle
        case loading(String)
        case ready
        case failed(String)
    }

    @Published var status: Status = .idle

    func load(_ model: CoreMLLanguageModel.Catalog = .qwen3_5_0_8B) async {
        status = .loading("Preparing…")
        do {
            let backend = try await CoreMLLanguageModel.load(model) { stage in
                Task { @MainActor in self.status = .loading(stage) }
            }
            SystemLanguageModel.default = SystemLanguageModel(backend: backend)
            status = .ready
        } catch {
            status = .failed(String(describing: error))
        }
    }
}

struct ChatView: View {
    @ObservedObject var loader: ModelLoader
    @State private var session: LanguageModelSession? = nil
    @State private var input = ""
    @State private var streamingText = ""
    @State private var entries: [Transcript.Entry] = []
    @State private var inFlight = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(entries.indices, id: \.self) { i in
                                bubble(for: entries[i])
                            }
                            if !streamingText.isEmpty {
                                bubble(for: .init(kind: .response, content: streamingText))
                                    .id("streaming")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: streamingText) { _, _ in
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }
                Divider()
                inputBar
            }
            .navigationTitle("PrivateFoundationModels")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if case .idle = loader.status { await loader.load() }
        }
        .onChange(of: loader.status.isReady) { _, ready in
            if ready, session == nil {
                session = LanguageModelSession(
                    instructions: "You are a concise assistant. Answer in two sentences."
                )
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch loader.status {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(loader.statusText).font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        case .ready:
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Ready — qwen3.5-0.8B on the Apple Neural Engine")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        case .failed(let message):
            Text("Load failed: \(message)").font(.caption).foregroundStyle(.red).padding(8)
        }
    }

    @ViewBuilder
    private func bubble(for entry: Transcript.Entry) -> some View {
        switch entry.kind {
        case .prompt:
            HStack {
                Spacer(minLength: 60)
                Text(entry.content)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .response:
            Text(entry.content)
                .padding(10)
                .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolCall:
            Text("→ \(entry.toolName ?? "?")(\(entry.toolArguments ?? "{}"))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        case .toolOutput:
            Text("← \(entry.toolName ?? "?") result: \(entry.content)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        case .instructions:
            EmptyView()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .disabled(!loader.status.isReady || inFlight)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || inFlight || !loader.status.isReady)
        }
        .padding(10)
    }

    private func send() async {
        guard let session else { return }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        inFlight = true
        defer { inFlight = false }

        entries.append(.init(kind: .prompt, content: prompt))
        streamingText = ""

        let stream = session.streamResponse(to: prompt)
        do {
            for try await snapshot in stream {
                streamingText = snapshot.content
            }
            let final = try await stream.collect()
            entries.append(.init(kind: .response, content: final.content))
        } catch {
            entries.append(.init(kind: .response, content: "Error: \(error)"))
        }
        streamingText = ""
    }
}

extension ModelLoader.Status {
    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

extension ModelLoader {
    var statusText: String {
        switch status {
        case .idle:                  return "Idle"
        case .loading(let stage):    return stage
        case .ready:                 return "Ready"
        case .failed(let message):   return "Failed: \(message)"
        }
    }
}

#Preview {
    ChatView(loader: ModelLoader())
}
