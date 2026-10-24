import TUIkit
import TUIkitMacros
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
extension TUIkit.EnvironmentValues {
    @Entry var qualified: Int = 3
}
