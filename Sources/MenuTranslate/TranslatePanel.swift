import SwiftUI

/// One gutter for the whole panel, so the language pickers, the text you type
/// and the translation all share a left edge.
private enum Metrics {
    static let gutter: CGFloat = 14
    static let textInsetV: CGFloat = 12
    static let paneMinHeight: CGFloat = 84

    /// TextEditor draws on an NSTextView with `textContainerInset` (0, 0) and a
    /// `lineFragmentPadding` of 5, so its text already sits 5pt in from the
    /// leading edge and flush with the top. Subtract that from the editor's own
    /// padding and the placeholder lands exactly on the caret.
    static let editorLinePadding: CGFloat = 5
    static var editorInsetH: CGFloat { gutter - editorLinePadding }
}

struct TranslatePanel: View {
    @ObservedObject var model: TranslatorModel
    let onQuit: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var copied = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            result
            Divider()
            footer
        }
        .frame(width: 400)
        .onAppear {
            inputFocused = true
            launchAtLogin = LoginItem.isEnabled
        }
        .onChange(of: model.focusRequest) { _ in
            inputFocused = true
            copied = false
            launchAtLogin = LoginItem.isEnabled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LanguagePicker(selection: $model.source, includeAuto: true, recents: model.recents)
            swapButton
            LanguagePicker(selection: $model.target, includeAuto: false, recents: model.recents)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
    }

    private var swapButton: some View {
        Button(action: model.swap) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSwap)
        .opacity(model.canSwap ? 1 : 0.3)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .help("Swap languages (⇧⌘S)")
    }

    // MARK: - Input

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.input.isEmpty {
                Text("Type to translate…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, Metrics.textInsetV)
                    .allowsHitTesting(false)
            }
            TextEditor(text: model.inputBinding)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Metrics.editorInsetH)
                .padding(.vertical, Metrics.textInsetV)
                .focused($inputFocused)
                .frame(minHeight: Metrics.paneMinHeight, maxHeight: 160)
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.input.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: .command)
                .help("Clear (⌘K)")
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
    }

    // MARK: - Output

    private var result: some View {
        ScrollView {
            Group {
                if model.output.isEmpty {
                    Text("Translation")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(model.output)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.textInsetV)
        }
        .frame(minHeight: Metrics.paneMinHeight, maxHeight: 180)
        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.35))
        .overlay(alignment: .bottomTrailing) {
            if !model.output.isEmpty {
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy translation (⇧⌘C)")
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            status
            Spacer(minLength: 4)
            optionsMenu
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var status: some View {
        switch model.status {
        case .translating:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Translating…")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        case .idle, .done:
            Text(idleStatus)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var idleStatus: String {
        if model.characterCount > TranslationService.characterLimit - 500 {
            return "\(model.characterCount)/\(TranslationService.characterLimit)"
        }
        if model.source.isAuto, let detected = model.detected {
            return "Detected: \(detected.name)"
        }
        return ""
    }

    private var optionsMenu: some View {
        Menu {
            Button("Translate now (⌘↩)") { model.translateNow() }
            Button("Open in Google Translate") { NSWorkspace.shared.open(model.webURL) }
            Divider()
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    LoginItem.set(enabled: enabled)
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
            Divider()
            Button("Quit MenuTranslate (⌘Q)", action: onQuit)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
    }

    // MARK: - Actions

    private func clear() {
        model.clear()
        copied = false
        inputFocused = true
    }

    private func copy() {
        model.copyOutput()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }
}
