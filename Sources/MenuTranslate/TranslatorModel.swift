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

    static let quickPickCount = 5

    @Published private(set) var input: String
    @Published private(set) var output = ""
    @Published private(set) var status: Status = .idle
    @Published private(set) var detected: Language?
    /// The language `output` is in: the target, or the fallback when the text
    /// was already in the target language.
    @Published private(set) var outputLanguage: Language?

    @Published var target: Language {
        didSet {
            guard target != oldValue else { return }
            defaults.set(target.code, forKey: Keys.target)
            noteRecent(target)
            retranslate()
        }
    }

    @Published var fallback: Language {
        didSet {
            guard fallback != oldValue else { return }
            defaults.set(fallback.code, forKey: Keys.fallback)
            noteRecent(fallback)
            retranslate()
        }
    }

    @Published var quickPickOnOpen: Bool {
        didSet { defaults.set(quickPickOnOpen, forKey: Keys.quickPickOnOpen) }
    }

    @Published private(set) var isPicking = false

    @Published var pickQuery = "" {
        didSet {
            // Language names contain no digits, so a digit always means "the
            // n-th option on screen", whether or not a filter is typed.
            guard let number = pickQuery.compactMap(\.wholeNumberValue).first else { return }
            pickQuery = pickQuery.filter { !$0.isNumber }
            let options = quickPickOptions
            if number >= 1, number <= options.count {
                pick(options[number - 1])
            }
        }
    }

    /// Bumped every time the panel opens so the view can re-focus the editor.
    @Published private(set) var focusRequest = 0

    private(set) var recents: [Language]

    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var cache: [String: TranslationResult] = [:]

    private enum Keys {
        static let target = "targetLanguage"
        static let fallback = "fallbackLanguage"
        static let input = "lastInput"
        static let recents = "recentLanguages"
        static let quickPickOnOpen = "pickLanguageOnOpen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        input = defaults.string(forKey: Keys.input) ?? ""
        let target = Language.resolve(defaults.string(forKey: Keys.target) ?? Locale.current.language.languageCode?.identifier, allowAuto: false)
        self.target = target
        fallback = defaults.string(forKey: Keys.fallback).flatMap(Language.named).flatMap { $0.isAuto ? nil : $0 }
            ?? (target.code == "en" ? .noFallback : Language.resolve("en", allowAuto: false))
        quickPickOnOpen = defaults.object(forKey: Keys.quickPickOnOpen) as? Bool ?? true
        recents = (defaults.stringArray(forKey: Keys.recents) ?? []).compactMap(Language.named).filter(\.isLanguage)
    }

    var isBusy: Bool { status == .translating }

    var characterCount: Int { input.count }

    var isOverLimit: Bool { characterCount > TranslationService.characterLimit }

    var webURL: URL {
        TranslationService.webURL(text: input, from: Language.autoCode, to: (outputLanguage ?? target).code)
    }

    func panelDidOpen() {
        focusRequest += 1
        pickQuery = ""
        isPicking = quickPickOnOpen
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
        outputLanguage = nil
        status = .idle
        defaults.removeObject(forKey: Keys.input)
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    // MARK: - Quick pick

    /// Without a filter: recent languages other than the current target, so 1
    /// always flips back to the last one used. With a filter: the best matches.
    var quickPickOptions: [Language] {
        let needle = pickQuery.trimmingCharacters(in: .whitespaces)
        let pool = needle.isEmpty ? suggestions : Language.search(needle, in: Language.all)
        return Array(pool.prefix(Self.quickPickCount))
    }

    func beginPicking() {
        pickQuery = ""
        isPicking = true
    }

    func endPicking() {
        isPicking = false
        pickQuery = ""
    }

    func pick(_ language: Language) {
        target = language
        endPicking()
    }

    /// ↩ keeps the current target unless a filter is typed.
    func submitPick() {
        if pickQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            endPicking()
        } else if let first = quickPickOptions.first {
            pick(first)
        }
    }

    private var suggestions: [Language] {
        let backups = [fallback, Language.named("en"), Locale.current.language.languageCode.flatMap { Language.named($0.identifier) }]
        var list: [Language] = []
        for language in recents + backups.compactMap({ $0 }) where language.isLanguage && language != target && !list.contains(language) {
            list.append(language)
        }
        return list
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
            outputLanguage = nil
            status = .idle
            return
        }

        guard !isOverLimit else {
            inFlight?.cancel()
            status = .failed("Too long — Google Translate accepts \(TranslationService.characterLimit) characters.")
            return
        }

        if let cached = cache[Self.cacheKey(text, target, fallback)] {
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

        let target = target
        let fallback = fallback
        inFlight = Task { [weak self] in
            do {
                let result = try await Self.translate(text, to: target, fallback: fallback)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // A newer request may have superseded this one mid-flight.
                guard target == self.target, fallback == self.fallback, text == self.trimmedInput else { return }
                self.remember(result, for: Self.cacheKey(text, target, fallback))
                self.apply(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    /// Detection alone would hand Danish text back unchanged with a Danish
    /// target. The fallback turns the pair into "whichever one it isn't in",
    /// at the cost of a second request in that case.
    private static func translate(_ text: String, to target: Language, fallback: Language) async throws -> TranslationResult {
        let first = try await TranslationService.translate(text, from: Language.autoCode, to: target.code)
        let detected = first.detectedSourceCode.flatMap(Language.named)
        guard detected == target, fallback.isLanguage, fallback != target else {
            return TranslationResult(text: first.text, detected: detected, language: target)
        }
        let second = try await TranslationService.translate(text, from: target.code, to: fallback.code)
        return TranslationResult(text: second.text, detected: detected, language: fallback)
    }

    private func apply(_ result: TranslationResult) {
        output = result.text
        detected = result.detected
        outputLanguage = result.language
        status = .done
    }

    private static func cacheKey(_ text: String, _ target: Language, _ fallback: Language) -> String {
        "\(target.code)|\(fallback.code)|\(text)"
    }

    private func remember(_ result: TranslationResult, for key: String) {
        if cache.count > 200 { cache.removeAll() }
        cache[key] = result
    }

    private func noteRecent(_ language: Language) {
        guard language.isLanguage else { return }
        recents.removeAll { $0 == language }
        recents.insert(language, at: 0)
        // One more than quick pick shows, since the current target is left out.
        recents = Array(recents.prefix(Self.quickPickCount + 1))
        defaults.set(recents.map(\.code), forKey: Keys.recents)
    }
}

private struct TranslationResult {
    let text: String
    let detected: Language?
    let language: Language
}
