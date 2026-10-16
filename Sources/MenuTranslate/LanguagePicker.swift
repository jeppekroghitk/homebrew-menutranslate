import SwiftUI

struct LanguagePicker: View {
    @Binding var selection: Language
    var extras: [Language] = []
    let recents: [Language]

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selection.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LanguageList(
                selection: $selection,
                extras: extras,
                recents: recents,
                dismiss: { isPresented = false }
            )
        }
    }
}

private struct LanguageList: View {
    @Binding var selection: Language
    let extras: [Language]
    let recents: [Language]
    let dismiss: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search languages", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = matches.first { choose(first) }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        section("Recent", languages: shortcuts)
                        section("All languages", languages: matches)
                    } else {
                        ForEach(matches) { row($0) }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 260)
        }
        .frame(width: 230)
        .onAppear { searchFocused = true }
    }

    private var pool: [Language] {
        extras + Language.all
    }

    private var matches: [Language] {
        Language.search(query, in: pool)
    }

    private var shortcuts: [Language] {
        extras + recents.filter { !extras.contains($0) }
    }

    @ViewBuilder
    private func section(_ title: String, languages: [Language]) -> some View {
        if !languages.isEmpty {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(languages) { row($0) }
        }
    }

    private func row(_ language: Language) -> some View {
        LanguageRow(
            language: language,
            isSelected: language == selection,
            action: { choose(language) }
        )
    }

    private func choose(_ language: Language) {
        selection = language
        dismiss()
    }
}

private struct LanguageRow: View {
    let language: Language
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
                Text(language.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.accentColor.opacity(0.18) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
