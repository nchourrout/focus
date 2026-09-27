import SwiftUI

// On the macOS 27 SDK, `@State` resolves to a macro whose implementation
// (SwiftUIMacros) ships only with the full Xcode, so Command Line Tools can no
// longer build a view that uses it. The property wrapper it expands to is still
// public, and a typealias reaches it without going through the macro. Same
// storage, same behavior, on every SDK. Use `@ViewState` in place of `@State`.
typealias ViewState<Value> = SwiftUI.State<Value>
