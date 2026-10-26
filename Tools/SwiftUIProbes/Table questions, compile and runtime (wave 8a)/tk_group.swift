import Foundation
import TUI

struct Person: Identifiable {
    let id: Int
    var givenName: String
    var email: String
}

@MainActor
struct GroupInference: View {
    @State var people: [Person] = []
    var body: some View {
        VStack {
            // A: does the builder alone infer it?
            Table(people) {
                TableColumn("Given", value: \.givenName)
                Group {
                    TableColumn("Label", value: \.email)
                }
            }
        }
    }
}

@MainActor
@TableColumnBuilder<Person, Never>
var groupProperty: some TableColumnContent<Person, Never> {
    Group {
        TableColumn("Label", value: \.email)
    }
}
