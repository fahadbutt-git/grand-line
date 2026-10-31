import SwiftUI

/// A view's own value, as @State. In the macOS 27 SDK @State is a compiler
/// plugin that only Xcode ships, so this holds SwiftUI's State type directly
/// and the app builds with the command line tools alone.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
