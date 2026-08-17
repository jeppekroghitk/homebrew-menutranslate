import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class TranslatorModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case translating
        case done
        case failed(String)
    }

    @Published private(set) var input: String
    @Published private(set) var output = ""
    @Published private(set) var status: Status = .idle
    @Published private(set) var detected: Language?

    @Published var source: Language {
        didSet {
            guard source != oldValue else { return }
            defaults.set(source.code, forKey: Keys.source)
            noteRecent(source)
            detected = nil
            retranslate()
        }
    }

    @Published var target: Language {
        didSet {
            guard target != oldValue else { return }
            defaults.set(target.code, forKey: Keys.target)
            noteRecent(target)
            retranslate()
        }
    }

    /// Bumped every time the panel opens so the view can re-focus the editor.
    @Published private(set) var focusRequest = 0

    private(set) var recents: [Language]

    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var cache: [String: Translation] = [:]

    private enum Keys {
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let input = "lastInput"
        static let recents = "recentLanguages"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        input = defaults.string(forKey: Keys.input) ?? ""
        source = Language.resolve(defaults.string(forKey: Keys.source) ?? Language.autoCode, allowAuto: true)
        target = Language.resolve(defaults.string(forKey: Keys.target) ?? Locale.current.language.languageCode?.identifier, allowAuto: false)
        recents = (defaults.stringArray(forKey: Keys.recents) ?? []).compactMap(Language.named)
    }

    var isBusy: Bool { status == .translating }

    var characterCount: Int { input.count }

    var isOverLimit: Bool { characterCount > TranslationService.characterLimit }

    var canSwap: Bool { !source.isAuto || detected != nil }

    var webURL: URL {
        TranslationService.webURL(text: input, from: source.code, to: target.code)
    }

    func panelDidOpen() {
        focusRequest += 1
        // Cheap catch-up: languages may have changed while the panel was closed,
        // or a previous attempt may have failed offline.
        if output.isEmpty, !trimmedInput.isEmpty {
            translateNow()
        }
    }

    /// Called on every keystroke. The work is deferred so a burst of typing costs
    /// one request instead of one per character.
    func setInput(_ text: String) {
        guard text != input else { return }
        input = text
        defaults.set(text, forKey: Keys.input)
        schedule(after: .milliseconds(450))
    }

    var inputBinding: Binding<String> {
        Binding(get: { self.input }, set: { self.setInput($0) })
    }

    func translateNow() {
        schedule(after: .zero)
    }

    func clear() {
        debounce?.cancel()
        inFlight?.cancel()
        input = ""
        output = ""
        detected = nil
        status = .idle
        defaults.removeObject(forKey: Keys.input)
    }

    /// Mirrors the website: with "Detect language" selected, swapping adopts the
    /// language Google actually detected rather than leaving auto on both sides.
    func swap() {
        let resolvedSource = source.isAuto ? detected : source
        guard let resolvedSource else { return }

        let translated = output
        source = target
        target = resolvedSource
        detected = nil

        if !translated.isEmpty {
            input = translated
            defaults.set(input, forKey: Keys.input)
        }
        translateNow()
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    // MARK: - Translating

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func retranslate() {
        guard !trimmedInput.isEmpty else { return }
        schedule(after: .milliseconds(80))
    }

    private func schedule(after delay: Duration) {
        debounce?.cancel()

        let text = trimmedInput
        guard !text.isEmpty else {
            inFlight?.cancel()
            output = ""
            detected = nil
            status = .idle
            return
        }

        guard !isOverLimit else {
            inFlight?.cancel()
            status = .failed("Too long — Google Translate accepts \(TranslationService.characterLimit) characters.")
            return
        }

        if let cached = cache[cacheKey(text)] {
            inFlight?.cancel()
            apply(cached)
            return
        }

        debounce = Task { [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            self?.run(text: text)
        }
    }

    private func run(text: String) {
        inFlight?.cancel()
        status = .translating

        let source = source.code
        let target = target.code
        inFlight = Task { [weak self] in
            do {
                let translation = try await TranslationService.translate(text, from: source, to: target)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // A newer request may have superseded this one mid-flight.
                guard source == self.source.code, target == self.target.code, text == self.trimmedInput else { return }
                self.remember(translation, for: text, source: source, target: target)
                self.apply(translation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ translation: Translation) {
        output = translation.text
        detected = translation.detectedSourceCode.flatMap(Language.named)
        status = .done
    }

    private func cacheKey(_ text: String) -> String {
        "\(source.code)|\(target.code)|\(text)"
    }

    private func remember(_ translation: Translation, for text: String, source: String, target: String) {
        if cache.count > 200 { cache.removeAll() }
        cache["\(source)|\(target)|\(text)"] = translation
    }

    private func noteRecent(_ language: Language) {
        guard !language.isAuto else { return }
        recents.removeAll { $0 == language }
        recents.insert(language, at: 0)
        recents = Array(recents.prefix(5))
        defaults.set(recents.map(\.code), forKey: Keys.recents)
    }
}
