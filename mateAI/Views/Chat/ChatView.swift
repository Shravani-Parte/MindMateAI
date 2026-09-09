import SwiftUI
import SwiftData

struct ChatView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @State private var viewModel: ChatViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let viewModel {
                    if viewModel.showCrisisBanner {
                        CrisisBanner()
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.messages) { message in
                                    MessageRow(message: message).id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let last = viewModel.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    HStack {
                        TextField(
                            "Share what's on your mind…",
                            text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)

                        Button {
                            viewModel.send(profile: profile)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                        }
                        .disabled(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding()
                }
            }
            .navigationTitle("Talk to MindMate")
            .onAppear {
                if viewModel == nil {
                    viewModel = ChatViewModel(context: context)
                }
            }
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(message.isUser ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.18))
                .foregroundStyle(message.isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

struct CrisisBanner: View {
    var body: some View {
        NavigationLink(destination: CrisisResourcesView()) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading) {
                    Text("You're not alone").bold()
                    Text("Tap for immediate support resources").font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .background(Color.red.opacity(0.15))
            .foregroundStyle(.red)
        }
    }
}
