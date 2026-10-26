//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+SizeDependent.swift
//
//  `.textVariant(.sizeDependent)`: a live text that steps down a ladder of
//  narrower spellings until one fits (decisions A32).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The size dependent variant preference allows the text to take the
/// available space into account when choosing the variant to display —
/// mirrors SwiftUI's `SizeDependentTextVariant`.
///
/// Made only through ``TextVariantPreference/sizeDependent``, as SwiftUI's is.
public struct SizeDependentTextVariant: TextVariantPreference, Sendable {}

extension TextVariantPreference where Self == SizeDependentTextVariant {
    /// The size dependent preference allows the text to take the available
    /// space into account when choosing the size variant to display.
    ///
    /// Of the spellings a text can give, it chooses the widest that fits the
    /// space it is offered without cutting a word or running past its line
    /// limit — wrapping first, as any text does. The live time formats are
    /// the texts with spellings to choose from (measured on macOS 15):
    ///
    /// | Text | Spellings, widest first |
    /// |---|---|
    /// | `.offset(to:)` | `1 hour, 2 minutes` → `1 hr, 2 min` → `1h 2m` |
    /// | `.reference(to:)`, relative | `2 minutes ago` → `2 min. ago` → `2m ago` |
    /// | `.reference(to:)`, absolute | `Friday, May 8` → `Fri, May 8` → `5/8` |
    /// | `.timer`, in units | `1 hour, 2 minutes` → `1 hr 2 min` → `1:02` |
    /// | `.stopwatch` | `01:02:05.50` → `1:02:05` → `1:02` → `1h` |
    /// | `Text(_:style: .relative)` | `1 hr, 2 min` → `1h 2m` |
    /// | `Text(_:style: .offset)` | `+1 hour` → `+1 hr` → `+1h` |
    /// | `Text(_:style: .date)` | `May 8, 2026` → `May 2026` → `2026` |
    /// | `Text(_:style: .time)` | `11:13 PM` → `11 PM` |
    ///
    /// in the environment's locale, and each live value in a key's
    /// interpolation or a concatenation steps down with the others. A text
    /// with none — any other text, a timer on its face — draws as it is.
    /// Nothing fits: the narrowest is drawn, cut as any text is.
    ///
    /// Only a text that asks pays: it measures each spelling it tries.
    public static var sizeDependent: SizeDependentTextVariant { SizeDependentTextVariant() }
}

// MARK: - The view

/// A text choosing its spelling by the space it is given: the measure and the
/// render each lay the spellings out, widest first, in the space their own
/// walk has, and take the first that ``Text/fitsWhole(width:height:context:)``.
/// Both read the same frame's words and the same rules, so a render given the
/// size its measure reported chooses as the measure did.
///
/// What `textVariant(_:)` returns for either preference: with
/// `choosesBySize` false (`.fixed`) it measures and draws the text as it is.
struct _SizeDependentText: View {
    let text: Text
    let choosesBySize: Bool

    var body: Never {
        fatalError("_SizeDependentText renders via Renderable")
    }

    /// The spelling to draw in `width` × `height` (rows; `nil` for no bound),
    /// having declared the text's next change as a live text does.
    private func chosen(width: Int, height: Int?, context: RenderContext, measuring: Bool) -> Text {
        // The declarations a live text makes — its wake, or a measure's
        // clocked read — are the widest spelling's: it changes at least as
        // often as any narrower one.
        guard let widest = text.readingLive(declaringIn: context, measuring: measuring) else { return text }
        let date = context.renderCache?.frameDate ?? Date()
        let rungs = text.liveSizeVariants(at: date, in: LiveTextEnvironment(context.environment))
        guard rungs.count > 1 else { return widest }
        return rungs.first { $0.fitsWhole(width: width, height: height, context: context) } ?? rungs[rungs.count - 1]
    }
}

extension _SizeDependentText: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard choosesBySize else { return text.sizeThatFits(proposal: proposal, context: context) }
        return chosen(
            width: proposal.width ?? context.availableWidth, height: proposal.height, context: context,
            measuring: true
        ).sizeThatFits(proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard choosesBySize else { return text.renderToBuffer(context: context) }
        return chosen(width: context.availableWidth, height: context.availableHeight, context: context, measuring: false)
            .renderToBuffer(context: context)
    }
}

// MARK: - The format styles' ladders

/// A format style of a date whose output has narrower spellings, for a
/// `.sizeDependent` text: TUI's `SystemFormatStyle`s.
protocol DateSizeVariantFormatStyle {
    /// The spellings of `input` in `locale`, widest first, the first being
    /// the format's own.
    func sizeVariants(of input: Date, locale: Locale) -> [String]
}
