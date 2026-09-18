import SwiftUI
import SwiftData

struct ChatView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @State private var viewModel: ChatViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    chatContent(viewModel)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("MindMate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let viewModel {
                        Button {
                            viewModel.startNewChat()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Start a new chat")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let viewModel {
                        backendPill(viewModel)
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = ChatViewModel(context: context)
                }
                LLMService.shared.refreshAvailability()
            }
        }
    }

    @ViewBuilder
    private func chatContent(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            if vm.showCrisisBanner {
                CrisisBanner()
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if vm.messages.isEmpty {
                            EmptyChatView(name: profile.name) { prompt in
                                vm.send(text: prompt, profile: profile)
                            }
                        } else {
                            ForEach(vm.messages, id: \.id) { message in
                                ChatBubble(message: message)
                            }
                            if vm.isGenerating && (vm.messages.last?.text.isEmpty ?? false) {
                                TypingBubble()
                                    .id("typing")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: vm.messages.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: vm.scrollTick) { _, _ in
                    scrollToLatest(proxy)
                }
            }

            inputBar(vm)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func inputBar(_ vm: ChatViewModel) -> some View {
        let sendable = !vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vm.isGenerating

        return HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Share what's on your mind…",
                text: Binding(get: { vm.draft }, set: { vm.draft = $0 }),
                axis: .vertical
            )
            .lineLimit(1...6)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Button {
                vm.send(profile: profile)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(sendable ? .white : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        sendable
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color(.systemGray4)),
                        in: Circle()
                    )
            }
            .disabled(!sendable)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func backendPill(_ vm: ChatViewModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.activeBackend == .template ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(vm.activeBackend == .template ? "Templates" : vm.activeBackend.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if let lastID = viewModel?.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyChatView: View {
    let name: String
    let onSelect: (String) -> Void

    private let suggestions: [String] = [
        "I've been feeling anxious about work lately",
        "I can't stop overthinking tonight",
        "I had a really good day — I want to celebrate",
        "I haven't been sleeping well, what can help?"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            Text("Hi \(name.isEmpty ? "there" : name), I'm MindMate")
                .font(.title2.bold())

            Text("I'm here to listen — without judgment.\nShare what's on your mind, or tap a prompt to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.footnote)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isUser {
                AssistantAvatar()
            }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .background(chatBackground)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: message.isUser ? 18 : 6,
                            bottomLeadingRadius: message.isUser ? 18 : 18,
                            bottomTrailingRadius: message.isUser ? 6 : 18,
                            topTrailingRadius: 18
                        )
                    )
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 320, alignment: message.isUser ? .trailing : .leading)

            if message.isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var chatBackground: some View {
        if message.isUser {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

struct AssistantAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.teal, Color.mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
            Image(systemName: "face.smiling")
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Typing indicator

struct TypingBubble: View {
    @State private var animate = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AssistantAvatar()
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1 : 0.5)
                        .opacity(animate ? 1 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 48)
        }
        .padding(.horizontal, 12)
        .onAppear { animate = true }
    }
}

// MARK: - Crisis banner

struct CrisisBanner: View {
    var body: some View {
        NavigationLink(destination: CrisisResourcesView()) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're not alone").bold()
                    Text("Tap for immediate support resources")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.red.opacity(0.25), Color.orange.opacity(0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

#Preview {
    ChatView(profile: UserProfile(name: "Sam"))
        .modelContainer(for: [UserProfile.self, DailyWellness.self, ChatSession.self, ChatMessage.self, CrisisEvent.self], inMemory: true)
}