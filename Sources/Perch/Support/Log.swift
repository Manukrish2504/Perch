import Foundation

/// Opt-in diagnostics: `PERCH_DEBUG=1 ./build/Perch.app/Contents/MacOS/Perch`.
/// Silent otherwise, so the shipped app never writes to stdout.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["PERCH_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("[perch] " + message() + "\n").utf8))
    }
}
