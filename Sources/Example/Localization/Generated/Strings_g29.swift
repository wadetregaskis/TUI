//  🖥️ TUI — A Terminal UI framework for Swift
//  Strings_g29.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the Text Input page's marked, highlighted editor
//  (`.textEditorMarks`): JSON whose brackets that do not match are marked.
//  English is the source of truth; every other language carries the same key
//  set.

// A sentence a translator reads whole is one string on one line.
// swiftlint:disable line_length

extension ExampleStrings {
    static let g29: [String: [String: String]] = [
        "en": [
            "page.textInput.marksSection": "Marks and highlighting · .textEditorMarks",
            "page.textInput.marksExplain": "A highlighter colours the JSON, and the app marks each bracket that doesn't match: ranges it finds in the text, which the editor draws over the colours and carries through every key. Mend or break a bracket to see the marks follow.",
            "page.textInput.marksNone": "Every bracket matches",
            "page.textInput.marksCount %@": "Brackets that don't match: %@",
        ],
        "de": [
            "page.textInput.marksSection": "Markierungen und Hervorhebung · .textEditorMarks",
            "page.textInput.marksExplain": "Ein Highlighter färbt das JSON, und die App markiert jede Klammer, die nicht passt: Bereiche, die sie im Text findet und die der Editor über die Farben zeichnet und bei jeder Taste mitführt. Repariere oder zerbrich eine Klammer, und die Markierungen folgen.",
            "page.textInput.marksNone": "Alle Klammern passen",
            "page.textInput.marksCount %@": "Klammern, die nicht passen: %@",
        ],
        "fr": [
            "page.textInput.marksSection": "Marques et coloration · .textEditorMarks",
            "page.textInput.marksExplain": "Un coloriseur colore le JSON, et l’app marque chaque crochet qui ne correspond pas : des plages qu’elle trouve dans le texte, que l’éditeur dessine par-dessus les couleurs et conserve à chaque touche. Réparez ou cassez un crochet pour voir les marques suivre.",
            "page.textInput.marksNone": "Tous les crochets correspondent",
            "page.textInput.marksCount %@": "Crochets sans correspondance : %@",
        ],
        "it": [
            "page.textInput.marksSection": "Segni ed evidenziazione · .textEditorMarks",
            "page.textInput.marksExplain": "Un evidenziatore colora il JSON e l’app segna ogni parentesi che non corrisponde: intervalli che trova nel testo, che l’editor disegna sopra i colori e porta con sé a ogni tasto. Ripara o rompi una parentesi per vedere i segni seguirla.",
            "page.textInput.marksNone": "Tutte le parentesi corrispondono",
            "page.textInput.marksCount %@": "Parentesi senza corrispondenza: %@",
        ],
        "es": [
            "page.textInput.marksSection": "Marcas y resaltado · .textEditorMarks",
            "page.textInput.marksExplain": "Un resaltador colorea el JSON y la app marca cada corchete que no casa: rangos que encuentra en el texto, que el editor dibuja sobre los colores y conserva con cada tecla. Arregla o rompe un corchete para ver cómo lo siguen las marcas.",
            "page.textInput.marksNone": "Todos los corchetes casan",
            "page.textInput.marksCount %@": "Corchetes que no casan: %@",
        ],
        "zh": [
            "page.textInput.marksSection": "标记与高亮 · .textEditorMarks",
            "page.textInput.marksExplain": "高亮器为 JSON 着色，应用则标记每个不匹配的括号：它在文本中找到的范围，编辑器把它们画在颜色之上，并随每次按键一起移动。修好或弄坏一个括号，就能看到标记跟着变化。",
            "page.textInput.marksNone": "所有括号都匹配",
            "page.textInput.marksCount %@": "不匹配的括号：%@",
        ],
        "ja": [
            "page.textInput.marksSection": "マークとハイライト · .textEditorMarks",
            "page.textInput.marksExplain": "ハイライターが JSON に色を付け、アプリは対応しない括弧ごとにマークを付けます。マークはアプリがテキスト中に見つけた範囲で、エディタは色の上に描き、キーを押すたびに一緒に動かします。括弧を直したり壊したりすると、マークが追従します。",
            "page.textInput.marksNone": "すべての括弧が対応しています",
            "page.textInput.marksCount %@": "対応しない括弧: %@",
        ],
    ]
}

// swiftlint:enable line_length
