import AppKit

// A plain AppKit bootstrap rather than a SwiftUI `App`: the notch panel needs
// direct control over activation policy and window level before anything is shown.
//
// Top-level code runs on the main thread but is not itself main-actor isolated,
// and `NSApplication.delegate` is a weak reference — hence the explicit hop and
// the strong global binding.
let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
