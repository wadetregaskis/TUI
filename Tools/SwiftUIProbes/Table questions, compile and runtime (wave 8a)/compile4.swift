import SwiftUI

struct TableCustomizationShapes: View {
    struct BugReport: Identifiable {
        let id: Int
        var title: String
        var reporter: String
    }

    @SceneStorage("BugReportTableConfig")
    private var columnCustomizationData: TableColumnCustomization<BugReport>
    @State private var columnCustomization = TableColumnCustomization<BugReport>()
    @State private var reports: [BugReport] = []
    @State private var selection = Set<BugReport.ID>()
    @State private var sortOrder = [KeyPathComparator(\BugReport.title)]

    var body: some View {
        VStack {
            Table(reports, columnCustomization: $columnCustomization) {
                TableColumn("Title", value: \.title)
                    .customizationID("title")
                    .disabledCustomizationBehavior(.visibility)
                TableColumn("Reporter", value: \.reporter)
                    .customizationID("reporter")
                    .defaultVisibility(.hidden)
            }
            Table(
                reports, selection: $selection, sortOrder: $sortOrder,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Title", value: \.title).customizationID("title")
            }
            Table(of: BugReport.self, columnCustomization: $columnCustomization) {
                TableColumn("Title", value: \.title).customizationID("title")
            } rows: {
                ForEach(reports)
            }
        }
        .onAppear {
            columnCustomization = columnCustomizationData
            columnCustomization[visibility: "reporter"] = .visible
            columnCustomization.resetOrder()
        }
    }
}
