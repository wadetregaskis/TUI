import SwiftUI
extension EnvironmentValues {
    @Entry var myCustomValue: String = "Default value"
    @Entry var anotherCustomValue = true
    @Entry var optionalOne: Int?
    @Entry public var publicOne: Double = 1.5
}
extension Transaction {
    @Entry var txValue: String = "tx"
}
extension ContainerValues {
    @Entry var cvValue: Int = 4
}
extension FocusedValues {
    @Entry var focusedThing: String?
}
