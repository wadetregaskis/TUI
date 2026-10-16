//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutPage+Room.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Who gets the room, and who is drawn on top: `.layoutPriority` (the
/// favoured text keeps its words while its sibling truncates), `.fixedSize`
/// (a text kept at its natural width in a frame too narrow for it), `.zIndex`
/// (which of two overlapping boxes is in front), and `.onGeometryChange`
/// (a view reporting the width it was given).
struct LayoutRoomDemo: View {
    @State private var frontIsFirst = true
    @State private var reportedWidth = 0

    var body: some View {
        DemoSection("page.layout.section.room") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.layout.room.priority").bold()
                HStack(spacing: 1) {
                    Text("page.layout.room.longFirst").lineLimit(1)
                    Text("page.layout.room.longSecond").lineLimit(1).layoutPriority(1)
                        .foregroundStyle(.palette.accent)
                }
                .frame(width: 50, alignment: .leading)
                .border(.palette.border)

                Text("page.layout.room.fixedSize").bold()
                // Two copies of one text, offered 30 cells between them: the
                // first takes what it is given and wraps, the second keeps the
                // width it wants.
                HStack(alignment: .top, spacing: 2) {
                    Text("page.layout.room.wraps")
                    Text("page.layout.room.wraps").fixedSize()
                        .foregroundStyle(.palette.accent)
                }
                .frame(width: 30, alignment: .leading)
                .border(.palette.border)

                Text("page.layout.room.zIndex").bold()
                HStack(spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        Text("page.layout.room.first").frame(width: 14, height: 3).border(.palette.accent)
                            .zIndex(frontIsFirst ? 1 : 0)
                        // Moved by padding, not `.offset`: an offset view draws
                        // above its siblings whatever its z-index (a terminal
                        // deviation, see `View.offset(x:y:)`).
                        Text("page.layout.room.second").frame(width: 14, height: 3).border(.palette.success)
                            .padding(.leading, 6).padding(.top, 1)
                            .zIndex(frontIsFirst ? 0 : 1)
                    }
                    .frame(width: 22, height: 4, alignment: .topLeading)
                    Button("page.layout.room.swap") { frontIsFirst.toggle() }
                }

                Text("page.layout.room.geometry").bold()
                Text("\(L("page.layout.room.width")) \(reportedWidth)")
                    .foregroundStyle(.palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: Int.self, of: { $0.size.width }, action: { reportedWidth = $0 })
                    .border(.palette.border)
            }
        }
    }
}
