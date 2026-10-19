//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g20.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the menu bar's own commands (`ExampleCommands`):
//  the File menu's page navigation and the View menu's theme and border
//  cycling, and the Menus page's section on the menu bar. The standard menus' own items (About, Quit, Undo, Find…, Show
//  Sidebar …) are TUIkit's strings. English is the source of truth; every
//  other language carries the same key set.

// A sentence a translator reads whole is one string on one line.
// swiftlint:disable line_length

extension ExampleStrings {
    static let g20: [String: [String: String]] = [
        "en": [
            "page.menus.menuBarSection": "Menu Bar · .commands",
            "page.menus.menuBarInstruction": "The row at the top of the window is the app's menu bar: the scene declares commands (ExampleCommands), and TUIkit adds the app's menu and Edit. F10 opens it, ← and → move between its menus, Esc closes it; a click on a title opens that menu, and Alt with a title's first letter does where the terminal sends Option as Meta. A command's key works with every menu closed.",
            "commands.mainMenu": "Main Menu",
            "commands.previousPage": "Previous Page",
            "commands.nextPage": "Next Page",
            "commands.nextPalette": "Next Palette",
            "commands.nextBorder": "Next Border Style",
        ],
        "de": [
            "page.menus.menuBarSection": "Menüleiste · .commands",
            "page.menus.menuBarInstruction": "Die Zeile oben im Fenster ist die Menüleiste der App: Die Szene deklariert Befehle (ExampleCommands), und TUIkit ergänzt das App-Menü und „Bearbeiten“. F10 öffnet sie, ← und → wechseln zwischen den Menüs, Esc schließt sie; ein Klick auf einen Titel öffnet dieses Menü, ebenso Alt mit dem ersten Buchstaben eines Titels, wo das Terminal die Wahltaste als Meta sendet. Die Taste eines Befehls wirkt auch bei geschlossenen Menüs.",
            "commands.mainMenu": "Hauptmenü",
            "commands.previousPage": "Vorherige Seite",
            "commands.nextPage": "Nächste Seite",
            "commands.nextPalette": "Nächste Palette",
            "commands.nextBorder": "Nächster Rahmenstil",
        ],
        "fr": [
            "page.menus.menuBarSection": "Barre des menus · .commands",
            "page.menus.menuBarInstruction": "La ligne en haut de la fenêtre est la barre des menus de l'app : la scène déclare des commandes (ExampleCommands), et TUIkit ajoute le menu de l'app et Modifier. F10 l'ouvre, ← et → passent d'un menu à l'autre, Échap la ferme ; un clic sur un titre ouvre ce menu, comme Alt avec la première lettre d'un titre là où le terminal envoie Option comme Meta. La touche d'une commande fonctionne menus fermés.",
            "commands.mainMenu": "Menu principal",
            "commands.previousPage": "Page précédente",
            "commands.nextPage": "Page suivante",
            "commands.nextPalette": "Palette suivante",
            "commands.nextBorder": "Style de bordure suivant",
        ],
        "it": [
            "page.menus.menuBarSection": "Barra dei menu · .commands",
            "page.menus.menuBarInstruction": "La riga in cima alla finestra è la barra dei menu dell'app: la scena dichiara dei comandi (ExampleCommands) e TUIkit aggiunge il menu dell'app e Modifica. F10 la apre, ← e → passano da un menu all'altro, Esc la chiude; un clic su un titolo apre quel menu, così come Alt con la prima lettera di un titolo dove il terminale invia Opzione come Meta. Il tasto di un comando funziona anche a menu chiusi.",
            "commands.mainMenu": "Menu principale",
            "commands.previousPage": "Pagina precedente",
            "commands.nextPage": "Pagina successiva",
            "commands.nextPalette": "Tavolozza successiva",
            "commands.nextBorder": "Stile del bordo successivo",
        ],
        "es": [
            "page.menus.menuBarSection": "Barra de menús · .commands",
            "page.menus.menuBarInstruction": "La fila superior de la ventana es la barra de menús de la app: la escena declara comandos (ExampleCommands) y TUIkit añade el menú de la app y Editar. F10 la abre, ← y → pasan de un menú a otro, Esc la cierra; un clic en un título abre ese menú, igual que Alt con la primera letra de un título donde el terminal envía Opción como Meta. La tecla de un comando funciona con los menús cerrados.",
            "commands.mainMenu": "Menú principal",
            "commands.previousPage": "Página anterior",
            "commands.nextPage": "Página siguiente",
            "commands.nextPalette": "Paleta siguiente",
            "commands.nextBorder": "Estilo de borde siguiente",
        ],
        "zh": [
            "page.menus.menuBarSection": "菜单栏 · .commands",
            "page.menus.menuBarInstruction": "窗口顶部的这一行是应用的菜单栏：场景声明了命令（ExampleCommands），TUIkit 加上应用菜单和“编辑”。F10 打开菜单栏，← 和 → 在菜单之间切换，Esc 关闭；点按标题会打开该菜单，在终端把 Option 作为 Meta 发送时，Alt 加标题的首字母也会打开。命令的快捷键在菜单关闭时同样有效。",
            "commands.mainMenu": "主菜单",
            "commands.previousPage": "上一页",
            "commands.nextPage": "下一页",
            "commands.nextPalette": "下一个调色板",
            "commands.nextBorder": "下一个边框样式",
        ],
        "ja": [
            "page.menus.menuBarSection": "メニューバー · .commands",
            "page.menus.menuBarInstruction": "ウインドウ最上部の行はアプリのメニューバーです。シーンがコマンドを宣言し（ExampleCommands）、TUIkit がアプリメニューと「編集」を加えます。F10 で開き、← と → でメニューを移動し、Esc で閉じます。タイトルをクリックするとそのメニューが開きます。端末が Option を Meta として送る場合は、Alt とタイトルの頭文字でも開きます。コマンドのキーはメニューを閉じたままでも使えます。",
            "commands.mainMenu": "メインメニュー",
            "commands.previousPage": "前のページ",
            "commands.nextPage": "次のページ",
            "commands.nextPalette": "次のパレット",
            "commands.nextBorder": "次の枠線スタイル",
        ],
    ]
}

// swiftlint:enable line_length
