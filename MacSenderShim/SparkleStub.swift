// Minimal stand-in for Sparkle.
//
// Sparkle is an SPM dependency, and SPM cannot be resolved here: this is a
// managed Mac with no admin rights, so the Xcode licence can never be accepted
// and xcodebuild/xcodegen are unusable. We build with swiftc directly instead.
//
// Sparkle only powers the "Check for Updates…" button. A locally built sender
// has no signed appcast to update from anyway, so stubbing it out loses nothing:
// the button simply stays disabled.
//
// Guarded so that if a real Sparkle ever becomes available, it wins.

#if !canImport(Sparkle)

import Foundation

/// KVO-observable so the app's `publisher(for: \.canCheckForUpdates)` still works.
@objc final class SPUUpdater: NSObject {
    @objc dynamic var canCheckForUpdates: Bool = false
    func checkForUpdates() {}
}

final class SPUStandardUpdaterController {
    let updater = SPUUpdater()
    init(startingUpdater: Bool, updaterDelegate: Any?, userDriverDelegate: Any?) {}
}

#endif
