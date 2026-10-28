//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationClip.swift
//
//  `animation`: a card duel that plays itself — a wizard against a kraken on
//  a felt table. Cards lift as they are picked, fly from the hand to the table
//  (matched geometry) and from the deck to the hand; the kraken's card grows
//  as it flies out of its hand and turns over; every spell throws a volley of
//  sprites across the table, the one hit shakes and flashes, its damage rises
//  off it and its hit points count down as the bar springs shorter; the turn
//  passes, the combo climbs, the log slides each move in. Then a
//  starfall, a victory banner and confetti, and the table is swept and dealt
//  again for the loop.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let animationClip = Clip(
    id: "animation",
    title: "Animation",
    columns: 112,
    rows: 30,
    output: 800,
    // Storm Call; the kraken's Riptide; Ember Volley and the Starfall that
    // finishes it; the banner; the table swept and the hand dealt again.
    script: [
        .camera(Shot(x: 0, y: 3, width: 87, height: 25)),
        .wait(0.4), .cue("pick 1"),
        .wait(0.35), .cue("pick 2"),
        .wait(0.45), .cue("play"),
        .wait(0.5), .cue("cast"),
        .wait(0.45), .cue("hit"),
        .wait(0.8), .cue("turn foe"),
        .wait(0.4), .cue("foe play"),
        .wait(0.6), .cue("flip"),
        .wait(0.5), .cue("foe cast"),
        .wait(0.5), .cue("foe hit"),
        .wait(0.8), .cue("turn you"),
        .wait(0.4), .cue("pick 1"),
        .wait(0.3), .cue("pick 2"),
        .wait(0.4), .cue("play"),
        .wait(0.5), .cue("cast"),
        .wait(0.45), .cue("hit"),
        .wait(0.35), .cue("pick 2"),
        .wait(0.35), .cue("play"),
        .wait(0.5), .cue("cast"),
        .wait(0.75), .cue("hit"),
        .wait(0.55), .cue("victory"),
        .wait(1.4), .cue("clear"),
        .wait(0.5), .cue("reset"),
        .wait(0.3), .cue("deal storm"),
        .wait(0.18), .cue("deal ember"),
        .wait(0.18), .cue("deal star"),
        .wait(0.6),
    ],
    run: { await AnimationApp.main() }
)

struct AnimationApp: App {
    var body: some Scene {
        WindowGroup("TUI · Starfall Duel") {
            CardDuel()
                .palette(AppleTerminalPalette(.grass))
        }
    }
}

/// Everything on the table.
struct DuelState {
    var hand: [DuelCard]
    var selected: Int? = 0
    var played: [DuelCard] = []
    var foeCard: DuelCard?
    var foeHand: [String]
    var deckTop = "c5"
    var deckCount = 18
    var serial = 100
    var krakenHP = 24
    var wrenHP = 30
    var mana = 5
    var combo = 0
    var yourTurn = true
    /// The duel's turn, counted from 1.
    var turn = 1
    /// Whose turns come next, the current one first: `true` is the player's.
    var turnOrder: [TurnToken] = (0..<6).map { TurnToken(id: $0, you: $0.isMultiple(of: 2)) }
    var log = Self.openingLog
    var flips = 0
    var volley: [Sprite] = []
    var volleyLength = 1.0
    var casts = 0
    var celebrations = 0
    var krakenHits = 0
    var wrenHits = 0
    var victory = false

    static let maxKraken = 24
    static let maxWren = 30

    static let openingHand: [DuelCard] = [
        DuelCard(id: "c0", spell: .clover), DuelCard(id: "c1", spell: .ice), DuelCard(id: "c2", spell: .storm),
        DuelCard(id: "c3", spell: .ember), DuelCard(id: "c4", spell: .star),
    ]

    static let openingLog: [LogLine] = [
        LogLine(id: 6, glyph: "🧊", title: "Ice Shard", detail: "3 dmg · slowed", colour: .rgb(150, 220, 255)),
        LogLine(id: 5, glyph: "🌀", title: "Kraken: Whirl", detail: "4 dmg to you", colour: .rgb(255, 130, 110)),
        LogLine(id: 4, glyph: "🍀", title: "Clover Ward", detail: "healed 3", colour: .rgb(170, 250, 140)),
        LogLine(id: 3, glyph: "🦑", title: "Kraken: Ink Jab", detail: "2 dmg to you", colour: .rgb(255, 130, 110)),
        LogLine(id: 2, glyph: "🔥", title: "Ember Volley", detail: "4 dmg", colour: .rgb(255, 180, 90)),
        LogLine(id: 1, glyph: "🎲", title: "Round 3", detail: "the Tide Kraken", colour: .rgb(255, 240, 165)),
        LogLine(id: 0, glyph: "🏆", title: "Round 2 won", detail: "+180 glory", colour: .rgb(255, 210, 80)),
    ]

    static let opening = Self(hand: openingHand, foeHand: ["f0", "f1", "f2", "f3"])

    mutating func newID() -> String {
        serial += 1
        return "c\(serial)"
    }

    mutating func note(_ glyph: String, _ title: String, _ detail: String, _ colour: Color) {
        serial += 1
        log.insert(LogLine(id: serial, glyph: glyph, title: title, detail: detail, colour: colour), at: 0)
    }
}

/// The duel: the felt table, and beside it the log, the turn order and the
/// relics.
struct CardDuel: View {
    @Namespace private var table
    @State private var game = DuelState.opening

    static let felt = Color.rgb(14, 92, 50)
    static let gold = Color.rgb(232, 190, 80)
    static let panel = Color.rgb(10, 66, 38)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                tableView
                DuelSidebar(log: game.log, turnOrder: game.turnOrder)
                    // Quicker than the table's moves: the log is the side
                    // show, and every frame it moves is a frame of the clip.
                    .animation(.easeOut(duration: 0.2), value: game.log)
            }
            Text(verbatim: " Space play · ←→ pick · D draw · Esc menu")
                .foregroundStyle(.palette.foregroundSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "🃏 Starfall Duel") }
        }
        .task {
            for await cue in ClipCues.stream() { apply(cue) }
        }
    }

    // MARK: - The table

    private var tableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            foeStrip
            turnRow
            battlefield
            wrenStrip
            Spacer(minLength: 0).frame(height: 1)
            handRow
        }
        .frame(width: 60, height: 23, alignment: .topLeading)
        .overlay(alignment: .center) { banner }
        .overlay(alignment: .topLeading) {
            SpriteLayer(sprites: game.volley, trigger: game.casts, duration: game.volleyLength)
        }
        .overlay(alignment: .topLeading) {
            SpriteLayer(sprites: Volley.confetti, trigger: game.celebrations, duration: 1.5)
        }
        .border(Self.gold, style: .rounded)
        .background(Self.felt)
    }

    /// The kraken: portrait, name, hit points, what it means to do; its hand.
    private var foeStrip: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(verbatim: game.krakenHP == 0 ? "💀" : "🐙")
                .frame(width: 6, height: 2)
                .border(Color.rgb(255, 120, 100), style: .rounded)
                .jolted(by: game.krakenHits, ground: game.krakenHP == 0 ? .rgb(70, 70, 80) : .rgb(20, 70, 130))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text(verbatim: "Tide Kraken").bold().strikethrough(game.krakenHP == 0)
                        .foregroundStyle(Color.rgb(255, 140, 120))
                    Text(verbatim: "Lv 7").foregroundStyle(.palette.foregroundSecondary)
                }
                hitPoints(game.krakenHP, of: DuelState.maxKraken, colour: .rgb(255, 90, 80))
                Text(verbatim: "Next: 🌊 Riptide (5)").foregroundStyle(Color.rgb(160, 230, 240))
            }
            .frame(width: 22, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(game.foeHand, id: \.self) { id in
                    CardBack()
                        .matchedGeometryEffect(id: id, in: table)
                        .frame(width: 6, height: 4)
                        .transition(.offset(y: -5).combined(with: .opacity))
                }
            }
        }
        .frame(height: 4, alignment: .top)
    }

    /// Whose turn, which turn it is, and the deck's count.
    private var turnRow: some View {
        HStack(spacing: 1) {
            Spacer(minLength: 0)
            Text(verbatim: game.yourTurn ? " ▶ YOUR TURN " : " ◀ KRAKEN'S TURN ")
                .bold()
                .foregroundStyle(Color.rgb(30, 20, 10))
                .background(game.yourTurn ? Color.rgb(255, 205, 60) : Color.rgb(255, 120, 100))
            Text(verbatim: "Turn \(game.turn)")
                .contentTransition(.numericText())
                .foregroundStyle(Color.rgb(120, 230, 255))
            Spacer(minLength: 0)
            Text(verbatim: "Deck \(game.deckCount)")
                .contentTransition(.numericText())
                .foregroundStyle(.palette.foregroundSecondary)
                .frame(width: 10, alignment: .leading)
        }
        .frame(height: 1)
    }

    /// The combo, the kraken's card, the player's pile, the deck.
    private var battlefield: some View {
        HStack(alignment: .top, spacing: 3) {
            comboBox
            ZStack {
                Self.slot("KRAKEN")
                if let foe = game.foeCard {
                    FlippingCard(spell: foe.spell, flips: game.flips)
                        .matchedGeometryEffect(id: foe.id, in: table)
                        .transition(.asymmetric(insertion: .opacity, removal: .offset(y: -6).combined(with: .opacity)))
                }
            }
            .frame(width: 10, height: 7)
            ZStack(alignment: .topLeading) {
                Self.slot("YOU").frame(width: 10, height: 7)
                ForEach(Array(game.played.enumerated()), id: \.element.id) { index, card in
                    CardFace(spell: card.spell)
                        .matchedGeometryEffect(id: card.id, in: table)
                        .frame(width: 10, height: 7)
                        // Drawn along, not padded: a padding's blank cells
                        // would cover the cards under it.
                        .offset(x: 3 * index)
                        .transition(.asymmetric(insertion: .opacity, removal: .offset(x: 20).combined(with: .opacity)))
                }
            }
            .frame(width: 19, height: 7, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                CardBack().frame(width: 10, height: 7).padding(.leading, 1).padding(.top, 1)
                CardBack()
                    .matchedGeometryEffect(id: game.deckTop, in: table)
                    .frame(width: 10, height: 7)
            }
            .frame(width: 11, height: 8, alignment: .topLeading)
        }
        .frame(height: 8, alignment: .top)
    }

    /// Where a card goes on the felt: a faint outline, and whose it is.
    private static func slot(_ owner: String) -> some View {
        Text(verbatim: owner)
            .foregroundStyle(Color.rgb(50, 140, 90))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color.rgb(40, 130, 80), style: .rounded)
    }

    /// The combo: a count, and a row of pips lighting one after another.
    private var comboBox: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(verbatim: "COMBO").bold().foregroundStyle(Self.gold)
            Spacer(minLength: 0)
            Text(verbatim: " ×\(game.combo) ")
                .bold()
                .contentTransition(.numericText())
                .foregroundStyle(game.combo > 0 ? Color.rgb(40, 10, 0) : Color.rgb(120, 170, 130))
                .background(game.combo > 1 ? Color.rgb(255, 120, 40) : game.combo > 0 ? Self.gold : Self.panel)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { pip in
                    Text(verbatim: "▰")
                        .foregroundStyle(pip < game.combo ? Color.rgb(255, 150, 40) : Color.rgb(40, 90, 60))
                        .animation(.bouncy(duration: 0.4).delay(0.06 * Double(pip)), value: game.combo)
                }
            }
        }
        .frame(width: 6, height: 5)
        .border(Color.rgb(255, 170, 70), style: .rounded)
        .background(Self.panel)
    }

    /// The player: name, hit points, mana gems.
    private var wrenStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text(verbatim: "🧙 Wren").bold().foregroundStyle(Color.rgb(170, 250, 140))
                hitPoints(game.wrenHP, of: DuelState.maxWren, colour: .rgb(120, 230, 90))
                Spacer(minLength: 0)
            }
            .jolted(by: game.wrenHits, ground: Self.felt)
            HStack(spacing: 0) {
                Text(verbatim: "Star-Mage · mana ").foregroundStyle(.palette.foregroundSecondary)
                ForEach(0..<5, id: \.self) { gem in
                    Text(verbatim: "◆")
                        .foregroundStyle(gem < game.mana ? Color.rgb(90, 220, 255) : Color.rgb(30, 70, 60))
                        .animation(.bouncy(duration: 0.4).delay(0.07 * Double(gem)), value: game.mana)
                }
                Text(verbatim: " \(game.mana)/5").foregroundStyle(Color.rgb(90, 220, 255))
            }
        }
        .frame(height: 2, alignment: .top)
    }

    /// The hand: the picked card lifted and lit.
    private var handRow: some View {
        HStack(alignment: .top, spacing: 1) {
            ForEach(game.hand.indices, id: \.self) { index in
                let lifted = game.selected == index && game.yourTurn
                CardFace(spell: game.hand[index].spell, lifted: lifted)
                    .matchedGeometryEffect(id: game.hand[index].id, in: table)
                    .frame(width: 10, height: 7)
                    .offset(y: lifted ? -1 : 0)
            }
        }
        .padding(.leading, 2)
        .frame(height: 7, alignment: .top)
    }

    /// A bar of hit points, springing to its length, and the count.
    private func hitPoints(_ points: Int, of most: Int, colour: Color) -> some View {
        HStack(spacing: 1) {
            Text(verbatim: "♥").foregroundStyle(colour)
            ZStack(alignment: .leading) {
                Color.rgb(8, 44, 26).frame(width: 14, height: 1)
                colour.frame(width: 14 * points / most, height: 1)
            }
            Text(verbatim: "").modifier(CountingText(value: Double(points), most: most))
        }
    }

    /// Victory, scaled in over the table.
    @ViewBuilder
    private var banner: some View {
        if game.victory {
            VStack(spacing: 0) {
                Text(verbatim: "🏆  V I C T O R Y  🏆").bold().frame(maxWidth: .infinity)
                Text(verbatim: "The Tide Kraken sinks!").frame(maxWidth: .infinity)
                Text(verbatim: "+250 glory").bold().foregroundStyle(Color.rgb(140, 30, 0)).frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.rgb(40, 20, 0))
            .frame(width: 28, height: 3)
            .border(Color.rgb(255, 250, 220), style: .doubleLine)
            .background(LinearGradient(colors: [.rgb(255, 230, 110), .rgb(255, 160, 40)], startPoint: .top, endPoint: .bottom))
            // Scaled in; faded out (scaled down, its words would be cut).
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
        }
    }
}

// MARK: - The script's cues

extension CardDuel {
    func apply(_ cue: String) {
        let words = cue.split(separator: " ").map(String.init)
        switch words.first {
        case "pick":
            withAnimation(.bouncy(duration: 0.4, extraBounce: 0.15)) { game.selected = Int(words.last ?? "") }
        case "play": withAnimation(.spring(duration: 0.6, bounce: 0.3)) { play() }
        case "cast":
            guard let card = game.played.last else { return }
            throwVolley(Volley.of(card.spell, pile: game.played.count))
        case "hit": withAnimation(.spring(duration: 0.7, bounce: 0.4)) { hit() }
        case "turn": turn(you: words.last == "you")
        case "foe": foe(words.last ?? "")
        case "flip": game.flips += 1
        case "deal": withAnimation(.spring(duration: 0.55, bounce: 0.3)) { deal(words) }
        case "victory":
            withAnimation(.bouncy(duration: 0.6, extraBounce: 0.2)) {
                game.victory = true
                game.celebrations += 1
                game.note("🏆", "Victory!", "+250 glory", .rgb(255, 210, 80))
            }
        case "clear": withAnimation(.smooth(duration: 0.55)) { clear() }
        case "reset": withAnimation(.spring(duration: 0.8, bounce: 0.35)) { reset() }
        default: break
        }
    }

    private func throwVolley(_ volley: (sprites: [Sprite], duration: Double)) {
        game.volley = volley.sprites
        game.volleyLength = volley.duration
        game.casts += 1
    }

    private func turn(you: Bool) {
        withAnimation(.snappy(duration: 0.35)) {
            game.yourTurn = you
            game.turn += 1
            game.selected = you ? 0 : nil
            if you { game.mana = 5 }
            let next = (game.turnOrder.last?.id ?? 0) + 1
            game.turnOrder.removeFirst()
            game.turnOrder.append(TurnToken(id: next, you: !(game.turnOrder.last?.you ?? true)))
        }
    }

    private func play() {
        guard let index = game.selected, game.hand.indices.contains(index) else { return }
        let card = game.hand.remove(at: index)
        game.played.append(card)
        game.mana -= card.spell.cost
        game.selected = nil
    }

    private func hit() {
        guard let card = game.played.last else { return }
        game.krakenHP = max(0, game.krakenHP - card.spell.power)
        game.krakenHits += 1
        game.combo += 1
        let detail = game.combo > 1 ? "\(card.spell.power) dmg ×\(game.combo) combo" : "\(card.spell.power) dmg"
        game.note(card.spell.glyph, card.spell == .star ? "STARFALL!" : card.spell.title, detail, card.spell.rim)
    }

    private func foe(_ step: String) {
        switch step {
        case "play":
            withAnimation(.spring(duration: 0.65, bounce: 0.25)) {
                guard let id = game.foeHand.popLast() else { return }
                game.foeCard = DuelCard(id: id, spell: .riptide)
            }
        case "cast": throwVolley(Volley.of(.riptide, pile: 0))
        case "hit":
            withAnimation(.spring(duration: 0.7, bounce: 0.4)) {
                game.wrenHP -= Spell.riptide.power
                game.wrenHits += 1
                game.note("🌊", "Kraken: Riptide", "5 dmg to you", .rgb(255, 130, 110))
            }
        default: break
        }
    }

    /// A card dealt from the deck into the hand, carried there.
    private func deal(_ words: [String]) {
        let spells: [String: Spell] = ["storm": .storm, "ember": .ember, "star": .star]
        let spell = spells[words.last ?? ""] ?? .storm
        game.hand.append(DuelCard(id: game.deckTop, spell: spell))
        game.deckTop = game.newID()
        game.deckCount -= 1
    }

    /// The table swept: the banner gone, the pile shuffled back into the deck.
    private func clear() {
        game.victory = false
        game.played = []
        game.foeCard = nil
        game.combo = 0
        game.deckCount += 3
    }

    /// The duel as it began, but for the three cards dealt after it.
    private func reset() {
        game.krakenHP = DuelState.maxKraken
        game.wrenHP = DuelState.maxWren
        game.mana = 5
        game.turn = 1
        game.selected = 0
        game.log = DuelState.openingLog
        game.foeHand.append("f\(game.serial)")
    }
}
