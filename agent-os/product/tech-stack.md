# Tech Stack

| Layer      | Choice                        | Why |
|------------|-------------------------------|-----|
| Language   | Swift 6.0 (language mode 5)   | Native notch/window control; no runtime to ship |
| UI         | SwiftUI + AppKit host         | SwiftUI for views, AppKit for the above-menu-bar panel |
| Charts     | Swift Charts (`import Charts`)| In-SDK, no dependency |
| Storage    | JSON snapshot in App Support  | Dataset is small enough to hold in memory |
| Cursor I/O | `SQLite3` C API (read-only)   | Cursor's store is a `.vscdb` SQLite file |
| Build      | SwiftPM + `build.sh`          | No Xcode on this machine (CLT only) |
| Deps       | **None.** Zero external packages | Everything needed is in the macOS SDK |

## Minimum target
macOS 14. Notch APIs (`safeAreaInsets`, `auxiliaryTopLeftArea`) are macOS 12+;
Swift Charts is macOS 13+.

## Build
`./build.sh` → SwiftPM release build → hand-assembled `Perch.app` bundle.
No Xcode project, no `xcodebuild` (Command Line Tools only).
