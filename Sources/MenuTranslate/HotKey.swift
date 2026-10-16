import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt
    let key: String

    static let standard = Shortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue,
        key: "T"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: UInt32 {
        var value = 0
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.shift) { value |= shiftKey }
        if flags.contains(.command) { value |= cmdKey }
        return UInt32(value)
    }

    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return characters.isEmpty ? "Key \(event.keyCode)" : characters
        }
    }
}

/// Owns the system-wide hotkey that toggles the panel. Carbon's
/// RegisterEventHotKey is still the only API for this that needs no
/// Accessibility permission.
@MainActor
final class HotKeyController: ObservableObject {
    @Published private(set) var shortcut: Shortcut?
    @Published private(set) var isRecording = false
    @Published private(set) var problem: String?

    private let defaults: UserDefaults
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let defaultsKey = "globalHotKey"
    private static let signature: OSType = 0x4D54_726E

    init(defaults: UserDefaults = .standard, action: @escaping () -> Void) {
        self.defaults = defaults
        self.action = action

        // A missing key means "never configured"; empty data means the user
        // removed the hotkey on purpose.
        if let data = defaults.data(forKey: Self.defaultsKey) {
            shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        } else {
            shortcut = .standard
        }

        installHandler()
        if let shortcut, !register(shortcut) {
            problem = "\(shortcut.display) is taken by another app"
        }
    }

    func startRecording() {
        unregister()
        problem = nil
        isRecording = true
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        if let shortcut { _ = register(shortcut) }
    }

    /// Receives every key press while recording, so the hotkey being replaced
    /// can be pressed again without toggling the panel.
    func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])

        if flags.isEmpty {
            switch Int(event.keyCode) {
            case kVK_Escape:
                cancelRecording()
            case kVK_Delete, kVK_ForwardDelete:
                save(nil)
                isRecording = false
            default:
                NSSound.beep()
            }
            return
        }

        guard !flags.isDisjoint(with: [.control, .option, .command]) else {
            NSSound.beep()
            return
        }

        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, key: Shortcut.keyName(for: event))
        isRecording = false
        if register(candidate) {
            save(candidate)
        } else {
            problem = "\(candidate.display) is taken by another app"
            if let shortcut { _ = register(shortcut) }
        }
    }

    private func save(_ shortcut: Shortcut?) {
        self.shortcut = shortcut
        problem = nil
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { controller.action() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
