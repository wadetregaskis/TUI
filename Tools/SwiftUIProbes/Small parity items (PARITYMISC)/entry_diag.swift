import TUI
import TUIMacros
struct NotAContainer {}
extension NotAContainer {
    @Entry var wrongPlace: Int = 1
}
extension EnvironmentValues {
    @Entry var noDefault: Int
}
extension FocusedValues {
    @Entry var notOptional: String
}
extension TUI.EnvironmentValues {
    @Entry var qualified: Int = 3
}
