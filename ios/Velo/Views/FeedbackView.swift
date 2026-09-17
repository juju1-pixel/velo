import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var webRouter: WebDestinationRouter
    @FocusState private var editorFocused: Bool
    @State private var text = ""
    @State private var saved = false
    @State private var saveFailed = false
    @State private var requestTask: Task<Void, Never>?
    private let store = LocalFeedbackStore()

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var editorText: Binding<String> {
        Binding(get: { text }, set: {
            text = String($0.prefix(LocalFeedbackStore.maximumLength))
            saved = false
            saveFailed = false
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: editorText)
                            .disabled(webRouter.isRequesting)
                            .focused($editorFocused)
                            .scrollContentBackground(.hidden)
                            .frame(height: 160)
                            .padding(8)
                            .accessibilityLabel("留言内容")
                            .accessibilityIdentifier("feedbackEditor")
                        if text.isEmpty {
                            Text("写下你的想法或建议…")
                                .foregroundStyle(VeloTheme.secondary)
                                .padding(.horizontal, 13).padding(.top, 16)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .background(VeloTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(VeloTheme.border, lineWidth: 1))
                    HStack {
                        Spacer()
                        Text("\(text.count) / \(LocalFeedbackStore.maximumLength)")
                            .monospacedDigit().accessibilityIdentifier("feedbackCharacterCount")
                    }.font(.caption).foregroundStyle(VeloTheme.secondary)

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if webRouter.isRequesting { ProgressView().tint(VeloTheme.onAccent) }
                            Text("提交留言").font(.headline)
                        }
                            .frame(maxWidth: .infinity).frame(minHeight: 50)
                            .foregroundStyle(VeloTheme.onAccent)
                            .background(isEmpty ? VeloTheme.secondary : VeloTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isEmpty || webRouter.isRequesting)
                    .accessibilityIdentifier("feedbackSubmit")

                    if saved {
                        Label("留言已提交", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(VeloTheme.accent)
                            .accessibilityIdentifier("feedbackSaved")
                    }
                    if saveFailed {
                        Label("提交失败，请重试。", systemImage: "exclamationmark.circle")
                            .foregroundStyle(VeloTheme.warning)
                            .accessibilityIdentifier("feedbackSaveFailed")
                    }
                }
                .font(.body)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(VeloTheme.foreground)
            .background(VeloTheme.background)
            .navigationTitle("留言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("feedbackClose")
                }
            }
        }
        .tint(VeloTheme.accent)
        .preferredColorScheme(.light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { requestTask?.cancel() }
    }

    private func submit() {
        guard !isEmpty, !webRouter.isRequesting else { return }
        do {
            let message = try store.save(text)
            text = ""
            saved = true
            saveFailed = false
            editorFocused = false
            requestTask = Task { await webRouter.handleFeedback(message.text) }
        } catch {
            saved = false
            saveFailed = true
        }
    }
}
