//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g21.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the Example's scenes: the main window's title,
//  which titles the terminal while it is in front; the Inspector window
//  (a `Window` scene, opened with `openWindow`), the Settings scene (a sheet),
//  and the Menus page's section on them. The menu bar's own items (Settings…,
//  Close Window, the Window menu) are TUIkit's strings. English is the source
//  of truth; every other language carries the same key set.

// A sentence a translator reads whole is one string on one line.
// swiftlint:disable line_length

extension ExampleStrings {
    static let g21: [String: [String: String]] = [
        "en": [
            "page.menus.scenesSection": "Scenes · openWindow, Settings",
            "page.menus.scenesInstruction": "The Example declares three scenes: this window, an Inspector window and Settings. The Inspector opens over the whole terminal, from here or the Window menu; this window carries on behind it, and Escape or Close brings it back as it was. Settings comes up as a sheet: from the link here, the app menu's Settings…, or ⌃,.",
            "page.menus.openInspector": "Open Inspector",
            "app.windowTitle": "TUIkit Example",
            "inspector.title": "Inspector",
            "inspector.explain": "A Window scene, opened over the main window with openWindow(id:). Its @SceneStorage is its own: the count below is kept for this window, apart from the main window's.",
            "inspector.count": "Count",
            "inspector.close": "Close Inspector",
            "settings.title": "Example Settings",
            "settings.explain": "The Settings scene, presented as a sheet over the window in front. These change the whole app at once.",
            "settings.uppercaseHeaders": "Uppercase section headers",
            "settings.boldButtons": "Bold buttons",
            "settings.done": "Done",
        ],
        "de": [
            "page.menus.scenesSection": "Szenen · openWindow, Settings",
            "page.menus.scenesInstruction": "Das Beispiel deklariert drei Szenen: dieses Fenster, ein Inspektor-Fenster und die Einstellungen. Der Inspektor öffnet sich über dem ganzen Terminal, von hier oder aus dem Menü „Fenster“; dieses Fenster läuft dahinter weiter, und Esc oder Schließen bringt es zurück, wie es war. Die Einstellungen erscheinen als Sheet: über den Link hier, „Einstellungen …“ im App-Menü oder ⌃,.",
            "page.menus.openInspector": "Inspektor öffnen",
            "app.windowTitle": "TUIkit-Beispiel",
            "inspector.title": "Inspektor",
            "inspector.explain": "Eine Window-Szene, mit openWindow(id:) über dem Hauptfenster geöffnet. Ihr @SceneStorage gehört ihr allein: Der Zähler unten wird für dieses Fenster geführt, getrennt von dem des Hauptfensters.",
            "inspector.count": "Zählen",
            "inspector.close": "Inspektor schließen",
            "settings.title": "Einstellungen des Beispiels",
            "settings.explain": "Die Settings-Szene, als Sheet über dem vorderen Fenster dargestellt. Diese Einstellungen ändern die ganze App auf einmal.",
            "settings.uppercaseHeaders": "Abschnittsüberschriften in Großbuchstaben",
            "settings.boldButtons": "Fette Tasten",
            "settings.done": "Fertig",
        ],
        "fr": [
            "page.menus.scenesSection": "Scènes · openWindow, Settings",
            "page.menus.scenesInstruction": "L'exemple déclare trois scènes : cette fenêtre, une fenêtre Inspecteur et les réglages. L'inspecteur s'ouvre sur tout le terminal, depuis ici ou le menu Fenêtre ; cette fenêtre continue derrière lui, et Échap ou Fermer la ramène telle qu'elle était. Les réglages s'affichent en feuille : par le lien ici, Réglages… dans le menu de l'app, ou ⌃,.",
            "page.menus.openInspector": "Ouvrir l'inspecteur",
            "app.windowTitle": "Exemple TUIkit",
            "inspector.title": "Inspecteur",
            "inspector.explain": "Une scène Window, ouverte par-dessus la fenêtre principale avec openWindow(id:). Son @SceneStorage lui appartient : le compte ci-dessous est gardé pour cette fenêtre, à part de celui de la fenêtre principale.",
            "inspector.count": "Compter",
            "inspector.close": "Fermer l'inspecteur",
            "settings.title": "Réglages de l'exemple",
            "settings.explain": "La scène Settings, présentée en feuille par-dessus la fenêtre au premier plan. Ces réglages changent toute l'app d'un coup.",
            "settings.uppercaseHeaders": "En-têtes de section en majuscules",
            "settings.boldButtons": "Boutons en gras",
            "settings.done": "Terminé",
        ],
        "it": [
            "page.menus.scenesSection": "Scene · openWindow, Settings",
            "page.menus.scenesInstruction": "L'esempio dichiara tre scene: questa finestra, una finestra Ispettore e le impostazioni. L'ispettore si apre su tutto il terminale, da qui o dal menu Finestra; questa finestra continua dietro di esso, ed Esc o Chiudi la riporta com'era. Le impostazioni compaiono come foglio: dal link qui, da Impostazioni… nel menu dell'app, o con ⌃,.",
            "page.menus.openInspector": "Apri ispettore",
            "app.windowTitle": "Esempio TUIkit",
            "inspector.title": "Ispettore",
            "inspector.explain": "Una scena Window, aperta sopra la finestra principale con openWindow(id:). Il suo @SceneStorage è suo: il conteggio qui sotto è tenuto per questa finestra, separato da quello della finestra principale.",
            "inspector.count": "Conta",
            "inspector.close": "Chiudi ispettore",
            "settings.title": "Impostazioni dell'esempio",
            "settings.explain": "La scena Settings, presentata come foglio sopra la finestra in primo piano. Queste impostazioni cambiano tutta l'app in una volta.",
            "settings.uppercaseHeaders": "Intestazioni di sezione in maiuscolo",
            "settings.boldButtons": "Pulsanti in grassetto",
            "settings.done": "Fine",
        ],
        "es": [
            "page.menus.scenesSection": "Escenas · openWindow, Settings",
            "page.menus.scenesInstruction": "El ejemplo declara tres escenas: esta ventana, una ventana Inspector y los ajustes. El inspector se abre sobre todo el terminal, desde aquí o desde el menú Ventana; esta ventana sigue detrás de él, y Esc o Cerrar la devuelve tal como estaba. Los ajustes aparecen como hoja: desde el enlace de aquí, Ajustes… en el menú de la app, o ⌃,.",
            "page.menus.openInspector": "Abrir inspector",
            "app.windowTitle": "Ejemplo de TUIkit",
            "inspector.title": "Inspector",
            "inspector.explain": "Una escena Window, abierta sobre la ventana principal con openWindow(id:). Su @SceneStorage es suyo: la cuenta de abajo se guarda para esta ventana, aparte de la de la ventana principal.",
            "inspector.count": "Contar",
            "inspector.close": "Cerrar inspector",
            "settings.title": "Ajustes del ejemplo",
            "settings.explain": "La escena Settings, presentada como hoja sobre la ventana de delante. Estos ajustes cambian toda la app a la vez.",
            "settings.uppercaseHeaders": "Encabezados de sección en mayúsculas",
            "settings.boldButtons": "Botones en negrita",
            "settings.done": "Hecho",
        ],
        "zh": [
            "page.menus.scenesSection": "场景 · openWindow、Settings",
            "page.menus.scenesInstruction": "本示例声明了三个场景：这个窗口、一个检查器窗口和设置。检查器从这里或“窗口”菜单打开，覆盖整个终端；这个窗口在它后面继续运行，按 Esc 或“关闭”即可原样回来。设置以表单形式出现：通过这里的链接、应用菜单中的“设置…”或 ⌃,。",
            "page.menus.openInspector": "打开检查器",
            "app.windowTitle": "TUIkit 示例",
            "inspector.title": "检查器",
            "inspector.explain": "一个 Window 场景，用 openWindow(id:) 在主窗口上方打开。它的 @SceneStorage 归它自己：下面的计数为这个窗口单独保存，与主窗口的分开。",
            "inspector.count": "计数",
            "inspector.close": "关闭检查器",
            "settings.title": "示例设置",
            "settings.explain": "Settings 场景，以表单形式显示在最前面的窗口之上。这些设置会一次性改变整个应用。",
            "settings.uppercaseHeaders": "大写的分区标题",
            "settings.boldButtons": "粗体按钮",
            "settings.done": "完成",
        ],
        "ja": [
            "page.menus.scenesSection": "シーン · openWindow、Settings",
            "page.menus.scenesInstruction": "このサンプルは 3 つのシーンを宣言しています。このウインドウ、インスペクタウインドウ、設定です。インスペクタはここか「ウインドウ」メニューから開き、端末全体を覆います。このウインドウはその後ろで動き続け、Esc か「閉じる」で元のまま戻ります。設定はシートとして表示されます。ここのリンク、アプリメニューの「設定…」、または ⌃, から開きます。",
            "page.menus.openInspector": "インスペクタを開く",
            "app.windowTitle": "TUIkit サンプル",
            "inspector.title": "インスペクタ",
            "inspector.explain": "Window シーンです。openWindow(id:) でメインウインドウの上に開きます。@SceneStorage はこのウインドウ専用で、下のカウントはメインウインドウとは別に保存されます。",
            "inspector.count": "数える",
            "inspector.close": "インスペクタを閉じる",
            "settings.title": "サンプルの設定",
            "settings.explain": "Settings シーンで、最前面のウインドウの上にシートとして表示されます。ここでの設定はアプリ全体に一度に反映されます。",
            "settings.uppercaseHeaders": "セクション見出しを大文字に",
            "settings.boldButtons": "太字のボタン",
            "settings.done": "完了",
        ],
    ]
}

// swiftlint:enable line_length
