// Does SwiftUI infer a key path's root inside a Group of columns?
import SwiftUI

struct Person: Identifiable {
    let id: Int
    var givenName: String
    var email: String
}

struct GroupInference: View {
    @State var people: [Person] = []
    @State var sortOrder = [KeyPathComparator(\Person.givenName)]
    var body: some View {
        Table(people) {
            TableColumn("Given", value: \.givenName)
            Group {
                TableColumn("Label", value: \.email)
            }
        }
        Table(people) {
            Group {
                TableColumn("Label", value: \.email)
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
