//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationClip+Cards.swift
//
//  The `animation` clip's pieces: the cards (faces, backs, and one that turns
//  over), the sprites a spell throws across the table, and the jolt a hit
//  gives whoever it lands on.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - Cards

/// The spells of the duel, each with its own colours.
enum Spell: Hashable {
    case clover, ice, storm, ember, star, riptide

    var glyph: String {
        switch self {
        case .clover: "🍀"
        case .ice: "🧊"
        case .storm: "⚡"
        case .ember: "🔥"
        case .star: "⭐"
        case .riptide: "🌊"
        }
    }

    /// The name, a word a line.
    var name: (String, String) {
        switch self {
        case .clover: ("Clover", "Ward")
        case .ice: ("Ice", "Shard")
        case .storm: ("Storm", "Call")
        case .ember: ("Ember", "Volley")
        case .star: ("Star-", "fall")
        case .riptide: ("Rip-", "tide")
        }
    }

    /// The name on one line.
    var title: String {
        switch self {
        case .star: "Starfall"
        case .riptide: "Riptide"
        default: "\(name.0) \(name.1)"
        }
    }

    var cost: Int {
        switch self {
        case .clover, .ice: 1
        case .ember: 2
        case .storm, .star, .riptide: 3
        }
    }

    /// What it does when it lands: damage, or (a ward) healing.
    var power: Int {
        switch self {
        case .clover: 3
        case .ice: 3
        case .storm: 6
        case .ember: 4
        case .star: 14
        case .riptide: 5
        }
    }

    /// The face, top to bottom.
    var colours: (Color, Color) {
        switch self {
        case .clover: (.rgb(96, 196, 72), .rgb(24, 104, 40))
        case .ice: (.rgb(110, 200, 250), .rgb(24, 88, 170))
        case .storm: (.rgb(150, 96, 255), .rgb(56, 24, 140))
        case .ember: (.rgb(255, 150, 40), .rgb(180, 30, 20))
        case .star: (.rgb(40, 60, 170), .rgb(10, 12, 60))
        case .riptide: (.rgb(40, 190, 210), .rgb(6, 60, 120))
        }
    }

    var rim: Color {
        switch self {
        case .clover: .rgb(200, 255, 170)
        case .ice: .rgb(200, 240, 255)
        case .storm: .rgb(255, 230, 90)
        case .ember: .rgb(255, 220, 140)
        case .star: .rgb(255, 210, 60)
        case .riptide: .rgb(160, 250, 255)
        }
    }
}

/// A card in a hand, on the table or in the deck: its id is the one its
/// matched geometry carries from place to place.
struct DuelCard: Identifiable, Hashable {
    let id: String
    let spell: Spell
}

/// A card's face: its cost and glyph, its name, its power. It fills whatever
/// frame it is given, so a card carried between frames of two sizes is laid
/// out at every size between; `named` false leaves only the colour (a card
/// turning over is too narrow for words).
struct CardFace: View {
    let spell: Spell
    var lifted = false
    var named = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if named {
                HStack(spacing: 0) {
                    Text(verbatim: "\(spell.cost)◆").bold().foregroundStyle(Color.rgb(140, 230, 255))
                    Spacer(minLength: 0)
                    Text(verbatim: spell.glyph)
                }
                Spacer(minLength: 0)
                Text(verbatim: spell.name.0).bold()
                Text(verbatim: spell.name.1).bold()
                Text(verbatim: spell == .clover ? "✚ \(spell.power)" : "✸ \(spell.power)")
                    .foregroundStyle(spell == .clover ? Color.rgb(200, 255, 170) : Color.rgb(255, 225, 120))
            }
        }
        .foregroundStyle(Color.rgb(255, 255, 245))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The border pads its content a cell either side; the face is laid
        // behind the border too, so the card is one block of colour.
        .border(lifted ? Color.rgb(255, 250, 170) : spell.rim, style: lifted ? .heavy : .rounded)
        .background(LinearGradient(colors: [spell.colours.0, spell.colours.1], startPoint: .top, endPoint: .bottom))
    }
}

/// A card's back: plum to magenta, a gold star at its heart. Fills its frame.
struct CardBack: View {
    var body: some View {
        Text(verbatim: "✦")
            .foregroundStyle(Color.rgb(255, 214, 90))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color.rgb(230, 180, 80), style: .rounded)
            .background(
                LinearGradient(
                    colors: [.rgb(150, 40, 170), .rgb(50, 16, 90)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
    }
}

/// The Kraken's card: face down as it comes, turned over when `flips` changes
/// — squeezed to an edge, back first, and opened out again face up.
struct FlippingCard: View {
    let spell: Spell
    let flips: Int

    var body: some View {
        KeyframeAnimator(initialValue: -1.0, trigger: flips) { turn in
            let squeeze = abs(turn)
            Group {
                if turn < 0 {
                    CardBack()
                } else {
                    CardFace(spell: spell, named: squeeze > 0.95)
                }
            }
            // Full width (whatever the frame is) at either end, so the card
            // carried in from the Kraken's hand follows the frame it flies in.
            .frame(maxWidth: squeeze > 0.99 ? .infinity : .fixed(max(2, Int((squeeze * 10).rounded()))))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.2, timingCurve: .easeIn)
                LinearKeyframe(1.0, duration: 0.25, timingCurve: .easeOut)
            }
        }
    }
}

// MARK: - Sprites

/// A glyph thrown across the table: from one cell to another, over a share of
/// its layer's timeline, eased, on an arc `arc` rows high at its middle.
struct Sprite {
    enum Ease { case out, accelerate, linear }

    var glyph: String
    var colour: Color = .rgb(255, 230, 120)
    var ground: Color?
    var from: (x: Int, y: Int)
    var to: (x: Int, y: Int)
    /// When it sets off and arrives, as shares of the layer's timeline.
    var start: Double
    var end: Double
    var arc = 0
    var ease = Ease.out

    /// Where it is at `time` (0…1 of the layer's timeline), or nil while it
    /// waits to set off and once it has arrived.
    func place(at time: Double) -> (x: Int, y: Int)? {
        let share = (time - start) / (end - start)
        guard share > 0, share < 1 else { return nil }
        let eased: Double =
            switch ease {
            case .out: 1 - (1 - share) * (1 - share) * (1 - share)
            case .accelerate: share * share
            case .linear: share
            }
        let lift = Double(arc) * 4 * share * (1 - share)
        let x = Double(from.x) + Double(to.x - from.x) * eased
        let y = Double(from.y) + Double(to.y - from.y) * eased - lift
        return (Int(x.rounded()), Int(y.rounded()))
    }
}

/// A layer of sprites over the table, thrown each time `trigger` changes:
/// one keyframe animator whose value is the time, each sprite drawn where the
/// time puts it. It rests at the end, where every sprite has arrived and gone.
struct SpriteLayer: View {
    let sprites: [Sprite]
    let trigger: Int
    let duration: Double

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: trigger) { time in
            ZStack(alignment: .topLeading) {
                ForEach(sprites.indices, id: \.self) { index in
                    if let place = sprites[index].place(at: time) {
                        sprite(sprites[index]).offset(x: place.x, y: place.y)
                    }
                }
            }
        } keyframes: { _ in
            KeyframeTrack { LinearKeyframe(1.0, duration: duration) }
        }
    }

    @ViewBuilder
    private func sprite(_ sprite: Sprite) -> some View {
        if let ground = sprite.ground {
            Text(verbatim: sprite.glyph).bold().foregroundStyle(sprite.colour).background(ground)
        } else {
            Text(verbatim: sprite.glyph).bold().foregroundStyle(sprite.colour)
        }
    }
}

/// The sprites each spell throws, in the table's own cells (its top-left
/// inside the felt's rim is 0, 0).
enum Volley {
    /// The Kraken's glyph in its portrait, and where its damage rises.
    static let kraken = (x: 4, y: 1)
    static let krakenDamage = (x: 13, y: 3)
    /// The Kraken's card, face up on the table.
    static let foeCard = (x: 17, y: 8)
    /// The player's strip, and where their damage rises.
    static let wren = (x: 8, y: 13)
    static let wrenDamage = (x: 32, y: 13)
    /// The middle of the table, where the banner is.
    static let middle = (x: 28, y: 10)

    /// The top card of the player's pile of `count`.
    static func pile(_ count: Int) -> (x: Int, y: Int) { (x: 30 + 3 * max(0, count - 1), y: 7) }

    /// A ring of sparks bursting out of `centre`.
    static func burst(
        _ glyphs: [String], colours: [Color], at centre: (x: Int, y: Int), reach: Int, start: Double, end: Double
    ) -> [Sprite] {
        let rays = [(2, 0), (2, 1), (1, 1), (0, 1), (-1, 1), (-2, 1), (-2, 0), (-1, -1), (1, -1), (3, 1)]
        return rays.enumerated().map { index, ray in
            Sprite(
                glyph: glyphs[index % glyphs.count], colour: colours[index % colours.count], from: centre,
                to: (max(0, centre.x + ray.0 * reach), max(0, centre.y + ray.1 * (reach + 1) / 2)),
                start: start + 0.02 * Double(index % 3), end: end)
        }
    }

    /// A number rising off whoever was hit.
    static func damage(_ text: String, at spot: (x: Int, y: Int), start: Double) -> Sprite {
        Sprite(
            glyph: text, colour: .rgb(255, 255, 255), ground: .rgb(220, 30, 50), from: spot,
            to: (spot.x, max(0, spot.y - 3)), start: start, end: 1.0)
    }

    /// What `spell` throws, and how long it takes, played from a pile of
    /// `pile` cards.
    static func of(_ spell: Spell, pile: Int) -> (sprites: [Sprite], duration: Double) {
        let from = Self.pile(pile)
        switch spell {
        case .storm:
            let bolts = (0..<6).map { (index: Int) -> Sprite in
                let start = 0.05 * Double(index)
                let origin = (x: from.x - index, y: from.y - index % 2)
                let target = (x: kraken.x + index % 3, y: kraken.y)
                return Sprite(glyph: "⚡", from: origin, to: target, start: start, end: start + 0.3, ease: .accelerate)
            }
            let sparks = burst(
                ["✦", "✧", "⚡"], colours: [.rgb(255, 240, 120), .rgb(190, 150, 255)], at: kraken, reach: 4,
                start: 0.42, end: 0.85)
            return (bolts + sparks + [damage(" ⚡ −6 ", at: krakenDamage, start: 0.4)], 1.1)
        case .ember:
            let fire = (0..<7).map { (index: Int) -> Sprite in
                let start = 0.05 * Double(index)
                let origin = (x: from.x + index % 2, y: from.y)
                let target = (x: kraken.x + index % 4, y: kraken.y + index % 2)
                return Sprite(glyph: "🔥", from: origin, to: target, start: start, end: start + 0.36, arc: 3)
            }
            let sparks = burst(
                ["✺", "✹", "•"], colours: [.rgb(255, 170, 40), .rgb(255, 90, 40), .rgb(255, 230, 120)], at: kraken,
                reach: 5, start: 0.45, end: 0.9)
            return (fire + sparks + [damage(" 🔥 −4 ", at: krakenDamage, start: 0.42)], 1.1)
        case .star:
            return (starfall(from: from), 1.6)
        case .riptide:
            let waves = (0..<8).map { (index: Int) -> Sprite in
                let start = 0.04 * Double(index)
                let target = (x: 2 + 5 * index, y: wren.y + index % 2)
                return Sprite(glyph: "🌊", from: foeCard, to: target, start: start, end: start + 0.4)
            }
            let spray = burst(
                ["💧", "∙", "°"], colours: [.rgb(150, 230, 255), .rgb(220, 250, 255)], at: (14, 13), reach: 4,
                start: 0.45, end: 0.85)
            return (waves + spray + [damage(" 🌊 −5 ", at: wrenDamage, start: 0.42)], 1.2)
        case .clover, .ice:
            return ([], 0.5)
        }
    }

    /// Stars swept in from every side of the table onto the Kraken, and a blast.
    private static func starfall(from pile: (x: Int, y: Int)) -> [Sprite] {
        let edges: [(x: Int, y: Int)] = [
            (58, 2), (56, 12), (40, 20), (20, 21), (2, 18), (0, 8), (30, 0), (46, 6), (10, 21), (52, 18), (34, 14),
            (24, 4), (58, 8), (4, 12),
        ]
        let glyphs = ["⭐", "🌟", "✨", "★"]
        let stars = edges.enumerated().map { (index: Int, edge: (x: Int, y: Int)) -> Sprite in
            let start = 0.025 * Double(index)
            let target = (x: kraken.x + index % 3, y: kraken.y + index % 2)
            return Sprite(
                glyph: glyphs[index % glyphs.count], colour: .rgb(255, 220, 80), from: edge, to: target,
                start: start, end: start + 0.32, arc: index % 3, ease: .accelerate)
        }
        let rise = Sprite(glyph: "⭐", from: pile, to: (pile.x, 0), start: 0, end: 0.2)
        let blast = burst(
            ["💥", "✦", "★", "✧"], colours: [.rgb(255, 240, 150), .rgb(255, 160, 60), .rgb(120, 200, 255)], at: kraken,
            reach: 6, start: 0.48, end: 0.95)
        let crit = Sprite(
            glyph: " ⭐ CRIT −14 ", colour: .rgb(30, 20, 0), ground: .rgb(255, 200, 40), from: krakenDamage,
            to: (krakenDamage.x, 0), start: 0.45, end: 1.0)
        return [rise] + stars + blast + [crit]
    }

    /// Confetti out of the banner to every corner of the table.
    static let confetti: [Sprite] = {
        let glyphs = ["🎉", "✦", "🎊", "●", "★", "▲", "✨", "◆", "⭐", "■"]
        let colours: [Color] = [
            .rgb(255, 90, 90), .rgb(255, 210, 60), .rgb(90, 220, 255), .rgb(200, 120, 255), .rgb(120, 255, 140),
        ]
        let targets: [(x: Int, y: Int)] = [
            (2, 1), (12, 0), (24, 1), (36, 0), (48, 1), (58, 2), (58, 9), (57, 16), (50, 21), (38, 22), (26, 21),
            (14, 22), (2, 20), (0, 13), (1, 6), (44, 4), (16, 5), (8, 16), (50, 14), (32, 3), (20, 18), (42, 18),
        ]
        return targets.enumerated().map { (index: Int, target: (x: Int, y: Int)) -> Sprite in
            let start = 0.02 * Double(index % 6)
            let end = 0.62 + 0.03 * Double(index % 5)
            return Sprite(
                glyph: glyphs[index % glyphs.count], colour: colours[index % colours.count], from: middle, to: target,
                start: start, end: end, arc: 2)
        }
    }()
}

// MARK: - Hits and numbers

/// The jolt a hit gives: a shake from side to side, and a red flash fading.
struct Jolt {
    var shake = 0.0
    var heat = 0.0
}

extension View {
    /// Shaken, and flashed over `ground`, each time `hits` changes.
    func jolted(by hits: Int, ground: Color) -> some View {
        keyframeAnimator(initialValue: Jolt(), trigger: hits) { content, jolt in
            content
                .background(Color.rgb(255, 60, 70).opacity(jolt.heat, over: ground))
                .offset(x: Int(jolt.shake.rounded()))
        } keyframes: { _ in
            KeyframeTrack(\.shake) {
                LinearKeyframe(-2.0, duration: 0.05)
                LinearKeyframe(2.0, duration: 0.067)
                LinearKeyframe(-2.0, duration: 0.067)
                LinearKeyframe(1.0, duration: 0.067)
                LinearKeyframe(0.0, duration: 0.05)
            }
            KeyframeTrack(\.heat) {
                LinearKeyframe(1.0, duration: 0.033)
                LinearKeyframe(0.0, duration: 0.5, timingCurve: .easeOut)
            }
        }
    }
}

/// A number counted through every whole value on its way to a new one, as an
/// animation carries it — hit points draining, or filling back up.
struct CountingText: ViewModifier, Animatable {
    var value: Double
    /// The most it can be: a spring overshoots, but hit points do not.
    var most: Int

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(verbatim: "\(min(most, max(0, Int(value.rounded()))))/\(most)").bold()
    }
}

// MARK: - The log

/// A line of the battle log.
struct LogLine: Identifiable, Hashable {
    let id: Int
    let glyph: String
    let title: String
    let detail: String
    let colour: Color
}

/// A turn in the turn order: `you` is the player's.
struct TurnToken: Identifiable, Hashable {
    let id: Int
    let you: Bool
}

// MARK: - The sidebar

/// Beside the table: the log, whose turn comes next, and the relics carried.
struct DuelSidebar: View {
    let log: [LogLine]
    let turnOrder: [TurnToken]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panel("BATTLE LOG", height: 14) {
                ForEach(Array(log.prefix(7))) { line in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(line.glyph) \(line.title)").bold().foregroundStyle(line.colour)
                        Text(verbatim: "   \(line.detail)").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            panel("TURN ORDER", height: 1) {
                HStack(spacing: 1) {
                    ForEach(turnOrder) { turn in
                        Text(verbatim: turn.you ? "🧙" : "🐙")
                            .background(turn.id == turnOrder.first?.id ? CardDuel.gold : CardDuel.panel)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            panel("RELICS", height: 1) {
                Text(verbatim: "🪶 🧿 🔔 🍯 🗝").foregroundStyle(CardDuel.gold)
            }
        }
        .frame(width: 22)
    }

    private func panel(_ title: String, height: Int, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title).bold().foregroundStyle(CardDuel.gold)
            content()
        }
        .frame(width: 18, height: height + 1, alignment: .topLeading)
        .border(Color.rgb(120, 180, 120), style: .rounded)
        .background(CardDuel.panel)
    }
}
