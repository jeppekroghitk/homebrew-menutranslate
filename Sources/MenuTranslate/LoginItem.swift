import Foundation
import ServiceManagement

/// Registers the app itself as a login item. Requires the binary to live in a
/// real bundle (see scripts/package.sh) — it silently does nothing when the
/// executable is run straight out of .build.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MenuTranslate: login item update failed — \(error.localizedDescription)")
        }
    }
}
