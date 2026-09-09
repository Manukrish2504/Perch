import SwiftUI

/// A stand-in for `@State`.
///
/// In the macOS 27 SDK, `@State` is implemented as a compiler macro whose plugin
/// (`SwiftUIMacros`) ships only with full Xcode — it is absent from the Command
/// Line Tools, which is all this project builds against. Every other SwiftUI
/// wrapper (`@Binding`, `@ObservedObject`, `@StateObject`, `@Environment`) is
/// still a plain property wrapper and works fine.
///
/// It is built on `@StateObject`, not on `State(initialValue:)`. Wrapping a bare
/// `State` compiles, but SwiftUI does not give it stable per-view storage that
/// way: declared defaults did not survive to first render (the dashboard opened
/// on whatever tab and range happened to be in the box). `@StateObject` has
/// well-defined identity and lifetime, so the box is created once per view
/// instance and its value persists across re-renders.
///
/// Usage is unchanged — `@Local private var tab: Tab = .overview`, and `$tab`
/// still projects a `Binding`.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }

    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }
}
