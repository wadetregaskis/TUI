//  🖥️ TUI — A Terminal UI framework for Swift
//  Strings_g20.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the menu bar's own commands (`ExampleCommands`):
//  the Go menu's page navigation, the View menu's text styling, the control
//  styles' names the Theme and Buttons pages show, the customizable top bar's
//  palette and border buttons, the Menus page's section on the menu bar, and
//  the credits the About alert shows. The standard menus' own items (About,
//  Quit, Undo, Find…, Show Sidebar, the View menu's Palette, Border Style and
//  Control Style …) are TUI's strings. English is the source of truth;
//  every other language carries the same key set.

// A sentence a translator reads whole is one string on one line.
// swiftlint:disable line_length

extension ExampleStrings {
    static let g20: [String: [String: String]] = [
        "en": [
            "page.menus.menuBarSection": "Menu Bar · .commands",
            "page.menus.menuBarInstruction": "The row at the top of the window is the app's menu bar: the scene declares commands (ExampleCommands), and TUI adds the app's menu, Edit and Help. F10 lights its first title and underlines each title's letter: ← and → move along the titles, ↓, ⏎ or a title's letter opens its menu, and Esc leaves. In a menu, ← and → move between the menus and Esc closes it. A click on a title opens that menu; press a title and drag down to choose the item you let go on; with a menu open, pointing at another title opens that one. Alt with a title's letter opens it where the terminal sends Option as Meta, and where the terminal reports Option held, the letters are underlined. A command's key works with every menu closed.",
            "commands.mainMenu": "Main Menu",
            "commands.previousPage": "Previous Page",
            "commands.nextPage": "Next Page",
            "commands.nextPalette": "Next Palette",
            "commands.nextBorder": "Next Border Style",
            "commands.go": "Go",
            "controlStyle.automatic": "Automatic",
            "controlStyle.block": "Block",
            "controlStyle.lines": "Lines",
            "controlStyle.braille": "Braille",
            "controlStyle.thickBraille": "Thick Braille",
            "controlStyle.blank": "Blank",
            "commands.textStyling": "Text Styling",
            "about.credits": "A tour of TUI: SwiftUI's views\nand controls, in a terminal.",
        ],
        "de": [
            "page.menus.menuBarSection": "Menüleiste · .commands",
            "page.menus.menuBarInstruction": "Die Zeile oben im Fenster ist die Menüleiste der App: Die Szene deklariert Befehle (ExampleCommands), und TUI ergänzt das App-Menü, „Bearbeiten“ und „Hilfe“. F10 hebt den ersten Titel hervor und unterstreicht den Buchstaben jedes Titels: ← und → wandern über die Titel, ↓, ⏎ oder der Buchstabe eines Titels öffnet dessen Menü, Esc beendet das. In einem Menü wechseln ← und → zwischen den Menüs, Esc schließt es. Ein Klick auf einen Titel öffnet dieses Menü; einen Titel drücken und nach unten ziehen wählt den Eintrag, über dem man loslässt; ist ein Menü offen, öffnet das Zeigen auf einen anderen Titel dessen Menü. Alt mit dem Buchstaben eines Titels öffnet es, wo das Terminal die Wahltaste als Meta sendet, und wo das Terminal die gehaltene Wahltaste meldet, sind die Buchstaben unterstrichen. Die Taste eines Befehls wirkt auch bei geschlossenen Menüs.",
            "commands.mainMenu": "Hauptmenü",
            "commands.previousPage": "Vorherige Seite",
            "commands.nextPage": "Nächste Seite",
            "commands.nextPalette": "Nächste Palette",
            "commands.nextBorder": "Nächster Rahmenstil",
            "commands.go": "Gehe zu",
            "controlStyle.automatic": "Automatisch",
            "controlStyle.block": "Block",
            "controlStyle.lines": "Linien",
            "controlStyle.braille": "Braille",
            "controlStyle.thickBraille": "Braille (dick)",
            "controlStyle.blank": "Leer",
            "commands.textStyling": "Textgestaltung",
            "about.credits": "Eine Tour durch TUI: die Views und\nBedienelemente von SwiftUI, im Terminal.",
        ],
        "fr": [
            "page.menus.menuBarSection": "Barre des menus · .commands",
            "page.menus.menuBarInstruction": "La ligne en haut de la fenêtre est la barre des menus de l'app : la scène déclare des commandes (ExampleCommands), et TUI ajoute le menu de l'app, Modifier et Aide. F10 met en évidence le premier titre et souligne la lettre de chaque titre : ← et → parcourent les titres, ↓, ⏎ ou la lettre d'un titre ouvre son menu, et Échap en sort. Dans un menu, ← et → passent d'un menu à l'autre et Échap le ferme. Un clic sur un titre ouvre ce menu ; appuyer sur un titre et glisser vers le bas choisit l'élément sur lequel on relâche ; un menu ouvert, pointer un autre titre ouvre celui-ci. Alt avec la lettre d'un titre l'ouvre là où le terminal envoie Option comme Meta, et là où le terminal signale Option maintenue, les lettres sont soulignées. La touche d'une commande fonctionne menus fermés.",
            "commands.mainMenu": "Menu principal",
            "commands.previousPage": "Page précédente",
            "commands.nextPage": "Page suivante",
            "commands.nextPalette": "Palette suivante",
            "commands.nextBorder": "Style de bordure suivant",
            "commands.go": "Aller",
            "controlStyle.automatic": "Automatique",
            "controlStyle.block": "Bloc",
            "controlStyle.lines": "Lignes",
            "controlStyle.braille": "Braille",
            "controlStyle.thickBraille": "Braille épais",
            "controlStyle.blank": "Vide",
            "commands.textStyling": "Style du texte",
            "about.credits": "Une visite de TUI : les vues et\ncontrôles de SwiftUI, dans un terminal.",
        ],
        "it": [
            "page.menus.menuBarSection": "Barra dei menu · .commands",
            "page.menus.menuBarInstruction": "La riga in cima alla finestra è la barra dei menu dell'app: la scena dichiara dei comandi (ExampleCommands) e TUI aggiunge il menu dell'app, Modifica e Aiuto. F10 evidenzia il primo titolo e sottolinea la lettera di ogni titolo: ← e → scorrono i titoli, ↓, ⏎ o la lettera di un titolo ne apre il menu, ed Esc esce. In un menu, ← e → passano da un menu all'altro ed Esc lo chiude. Un clic su un titolo apre quel menu; premere un titolo e trascinare in basso sceglie la voce su cui si rilascia; con un menu aperto, puntare un altro titolo apre quello. Alt con la lettera di un titolo lo apre dove il terminale invia Opzione come Meta, e dove il terminale segnala Opzione tenuto premuto, le lettere sono sottolineate. Il tasto di un comando funziona anche a menu chiusi.",
            "commands.mainMenu": "Menu principale",
            "commands.previousPage": "Pagina precedente",
            "commands.nextPage": "Pagina successiva",
            "commands.nextPalette": "Tavolozza successiva",
            "commands.nextBorder": "Stile del bordo successivo",
            "commands.go": "Vai",
            "controlStyle.automatic": "Automatico",
            "controlStyle.block": "Blocco",
            "controlStyle.lines": "Linee",
            "controlStyle.braille": "Braille",
            "controlStyle.thickBraille": "Braille spesso",
            "controlStyle.blank": "Vuoto",
            "commands.textStyling": "Stile del testo",
            "about.credits": "Un giro di TUI: le viste e i controlli\ndi SwiftUI, in un terminale.",
        ],
        "es": [
            "page.menus.menuBarSection": "Barra de menús · .commands",
            "page.menus.menuBarInstruction": "La fila superior de la ventana es la barra de menús de la app: la escena declara comandos (ExampleCommands) y TUI añade el menú de la app, Editar y Ayuda. F10 resalta el primer título y subraya la letra de cada título: ← y → recorren los títulos, ↓, ⏎ o la letra de un título abre su menú, y Esc sale. En un menú, ← y → pasan de un menú a otro y Esc lo cierra. Un clic en un título abre ese menú; pulsar un título y arrastrar hacia abajo elige el elemento sobre el que se suelta; con un menú abierto, señalar otro título abre ese. Alt con la letra de un título lo abre donde el terminal envía Opción como Meta, y donde el terminal informa de Opción pulsada, las letras aparecen subrayadas. La tecla de un comando funciona con los menús cerrados.",
            "commands.mainMenu": "Menú principal",
            "commands.previousPage": "Página anterior",
            "commands.nextPage": "Página siguiente",
            "commands.nextPalette": "Paleta siguiente",
            "commands.nextBorder": "Estilo de borde siguiente",
            "commands.go": "Ir",
            "controlStyle.automatic": "Automático",
            "controlStyle.block": "Bloque",
            "controlStyle.lines": "Líneas",
            "controlStyle.braille": "Braille",
            "controlStyle.thickBraille": "Braille grueso",
            "controlStyle.blank": "Vacío",
            "commands.textStyling": "Estilo del texto",
            "about.credits": "Un recorrido por TUI: las vistas y los\ncontroles de SwiftUI, en un terminal.",
        ],
        "zh": [
            "page.menus.menuBarSection": "菜单栏 · .commands",
            "page.menus.menuBarInstruction": "窗口顶部的这一行是应用的菜单栏：场景声明了命令（ExampleCommands），TUI 加上应用菜单、“编辑”和“帮助”。F10 会高亮第一个标题，并给每个标题的字母加下划线：← 和 → 在标题之间移动，↓、⏎ 或标题的字母会打开该菜单，Esc 退出。在菜单中，← 和 → 在菜单之间切换，Esc 关闭菜单。点按标题会打开该菜单；按住标题向下拖动，在哪一项上松开就选择哪一项；菜单打开时，指向另一个标题会打开那个菜单。在终端把 Option 作为 Meta 发送时，Alt 加标题的字母会打开该菜单；在终端报告按住 Option 时，这些字母会加下划线。命令的快捷键在菜单关闭时同样有效。",
            "commands.mainMenu": "主菜单",
            "commands.previousPage": "上一页",
            "commands.nextPage": "下一页",
            "commands.nextPalette": "下一个调色板",
            "commands.nextBorder": "下一个边框样式",
            "commands.go": "前往",
            "controlStyle.automatic": "自动",
            "controlStyle.block": "块",
            "controlStyle.lines": "线条",
            "controlStyle.braille": "盲文",
            "controlStyle.thickBraille": "粗盲文",
            "controlStyle.blank": "空白",
            "commands.textStyling": "文字样式",
            "about.credits": "TUI 导览：SwiftUI 的视图\n和控件，在终端里。",
        ],
        "ja": [
            "page.menus.menuBarSection": "メニューバー · .commands",
            "page.menus.menuBarInstruction": "ウインドウ最上部の行はアプリのメニューバーです。シーンがコマンドを宣言し（ExampleCommands）、TUI がアプリメニュー、「編集」、「ヘルプ」を加えます。F10 で最初のタイトルが強調され、各タイトルの文字に下線が付きます。← と → でタイトルを移動し、↓、⏎、またはタイトルの文字でそのメニューが開き、Esc で抜けます。メニューの中では、← と → でメニューを移動し、Esc で閉じます。タイトルをクリックするとそのメニューが開きます。タイトルを押したまま下へドラッグし、離した項目が選ばれます。メニューが開いているときは、別のタイトルを指すとそのメニューが開きます。端末が Option を Meta として送る場合は、Alt とタイトルの文字でも開き、端末が Option の押下を報告する場合は、その文字に下線が付きます。コマンドのキーはメニューを閉じたままでも使えます。",
            "commands.mainMenu": "メインメニュー",
            "commands.previousPage": "前のページ",
            "commands.nextPage": "次のページ",
            "commands.nextPalette": "次のパレット",
            "commands.nextBorder": "次の枠線スタイル",
            "commands.go": "移動",
            "controlStyle.automatic": "自動",
            "controlStyle.block": "ブロック",
            "controlStyle.lines": "線",
            "controlStyle.braille": "点字",
            "controlStyle.thickBraille": "太い点字",
            "controlStyle.blank": "なし",
            "commands.textStyling": "テキストのスタイル",
            "about.credits": "TUI ツアー：SwiftUI のビューと\nコントロールをターミナルで。",
        ],
    ]
}

// swiftlint:enable line_length
