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
    @ObservedObject var hotKeys: HotKeyController
    let onQuit: () -> Void

    private enum Field {
        case input
        case pick
    }

    @FocusState private var focus: Field?
    @State private var copied = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        // Quick pick takes over the header and the editor rather than adding
        // rows, so the popover keeps one fixed size.
        VStack(spacing: 0) {
            if model.isPicking {
                pickHeader
                Divider()
                pickOptions
            } else {
                header
                Divider()
                editor
            }
            Divider()
            result
            Divider()
            footer
        }
        .frame(width: 400)
        .onAppear {
            focus = model.isPicking ? .pick : .input
            launchAtLogin = LoginItem.isEnabled
        }
        .onChange(of: model.focusRequest) { _ in
            focus = model.isPicking ? .pick : .input
            copied = false
            launchAtLogin = LoginItem.isEnabled
        }
        .onChange(of: model.isPicking) { picking in
            focus = picking ? .pick : .input
        }
        .onChange(of: focus) { field in
            // ⇥ or a click in the text box skips the pick.
            if field == .input, model.isPicking { model.endPicking() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("To")
                .foregroundStyle(.secondary)
            LanguagePicker(selection: $model.target, recents: model.recents)
            Text("\(model.target.name) →")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Text already in \(model.target.name) is translated to this language instead")
            LanguagePicker(selection: $model.fallback, extras: [.noFallback], recents: model.recents)
        }
        .font(.system(size: 12))
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
    }

    // MARK: - Quick pick

    private var pickHeader: some View {
        HStack(spacing: 8) {
            Text("To")
                .foregroundStyle(.secondary)
            TextField("Type a language…", text: $model.pickQuery)
                .textFieldStyle(.plain)
                .focused($focus, equals: .pick)
                .onSubmit(model.submitPick)
                .onAppear { focus = .pick }
            Text(pickSubmitHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }

    private var pickSubmitHint: String {
        if model.pickQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return "↩ keep \(model.target.name)"
        }
        return model.quickPickOptions.first.map { "↩ \($0.name)" } ?? ""
    }

    private var pickOptions: some View {
        let options = model.quickPickOptions
        let filtering = !model.pickQuery.trimmingCharacters(in: .whitespaces).isEmpty
        return Group {
            if options.isEmpty {
                Text("No language matches “\(model.pickQuery)”")
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, language in
                        PickChip(
                            number: index + 1,
                            language: language,
                            isDefault: filtering && index == 0,
                            action: { model.pick(language) }
                        )
                    }
                }
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: Metrics.paneMinHeight, alignment: .topLeading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.textInsetV)
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
                .focused($focus, equals: .input)
                .onAppear { focus = .input }
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
        if hotKeys.isRecording {
            Text("Press the new hotkey · ⌫ removes it · esc cancels")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        } else if let problem = hotKeys.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if model.isPicking {
            Text("Type to filter · 1–\(TranslatorModel.quickPickCount) to choose · ⇥ skip")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            translationStatus
        }
    }

    @ViewBuilder
    private var translationStatus: some View {
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
        guard let detected = model.detected else { return "" }
        if let language = model.outputLanguage, language != model.target {
            return "Detected \(detected.name) → \(language.name)"
        }
        return "Detected \(detected.name)"
    }

    private var optionsMenu: some View {
        Menu {
            Button("Translate now (⌘↩)") { model.translateNow() }
            Button("Choose language (⌘L)") { model.beginPicking() }
            Button("Open in Google Translate") { NSWorkspace.shared.open(model.webURL) }
            Divider()
            Toggle("Choose language on open", isOn: $model.quickPickOnOpen)
            Button(hotKeys.shortcut.map { "Change hotkey (\($0.display))…" } ?? "Set hotkey…") {
                hotKeys.startRecording()
            }
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
        focus = .input
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

private struct PickChip: View {
    let number: Int
    let language: Language
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(language.name)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDefault ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isDefault ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Lays chips out left to right and wraps them onto new rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
