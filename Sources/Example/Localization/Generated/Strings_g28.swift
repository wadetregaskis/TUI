//  🖥️ TUI — A Terminal UI framework for Swift
//  Strings_g28.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the Terminal page's hand-off section
//  (`\.handOffTerminal`): a note edited in the person's own editor. English is
//  the source of truth; every other language carries the same key set.

// A sentence a translator reads whole is one string on one line.
// swiftlint:disable line_length

extension ExampleStrings {
    static let g28: [String: [String: String]] = [
        "en": [
            "page.terminal.handOffSection": "Another program · \\.handOffTerminal",
            "page.terminal.handOffExplain": "The app hands the terminal to another program, here your $VISUAL or $EDITOR (vi if neither is set), and takes it back when the program ends. ⌃C and ⌃Z are the program's while it runs.",
            "page.terminal.handOffNote": "Note",
            "page.terminal.handOffDefault": "Edit me, save, and quit the editor.",
            "page.terminal.handOffEdit": "Edit in $EDITOR",
            "page.terminal.handOffSaved": "Brought back from the editor",
            "page.terminal.handOffStatus": "The editor ended with status",
            "page.terminal.handOffUnavailable": "No programs can be started here",
        ],
        "de": [
            "page.terminal.handOffSection": "Ein anderes Programm · \\.handOffTerminal",
            "page.terminal.handOffExplain": "Die App übergibt das Terminal einem anderen Programm, hier deinem $VISUAL oder $EDITOR (vi, wenn keiner gesetzt ist), und nimmt es zurück, wenn das Programm endet. Solange es läuft, gehören ⌃C und ⌃Z dem Programm.",
            "page.terminal.handOffNote": "Notiz",
            "page.terminal.handOffDefault": "Bearbeite mich, speichere und beende den Editor.",
            "page.terminal.handOffEdit": "In $EDITOR bearbeiten",
            "page.terminal.handOffSaved": "Aus dem Editor zurückgeholt",
            "page.terminal.handOffStatus": "Der Editor endete mit Status",
            "page.terminal.handOffUnavailable": "Hier lassen sich keine Programme starten",
        ],
        "fr": [
            "page.terminal.handOffSection": "Un autre programme · \\.handOffTerminal",
            "page.terminal.handOffExplain": "L’app confie le terminal à un autre programme, ici votre $VISUAL ou $EDITOR (vi si aucun n’est défini), et le reprend quand le programme se termine. Pendant qu’il tourne, ⌃C et ⌃Z sont à lui.",
            "page.terminal.handOffNote": "Note",
            "page.terminal.handOffDefault": "Modifiez-moi, enregistrez et quittez l’éditeur.",
            "page.terminal.handOffEdit": "Modifier dans $EDITOR",
            "page.terminal.handOffSaved": "Ramenée de l’éditeur",
            "page.terminal.handOffStatus": "L’éditeur s’est terminé avec le code",
            "page.terminal.handOffUnavailable": "Aucun programme ne peut être lancé ici",
        ],
        "it": [
            "page.terminal.handOffSection": "Un altro programma · \\.handOffTerminal",
            "page.terminal.handOffExplain": "L’app passa il terminale a un altro programma, qui il tuo $VISUAL o $EDITOR (vi se nessuno è impostato), e lo riprende quando il programma termina. Mentre è in esecuzione, ⌃C e ⌃Z sono suoi.",
            "page.terminal.handOffNote": "Nota",
            "page.terminal.handOffDefault": "Modificami, salva ed esci dall’editor.",
            "page.terminal.handOffEdit": "Modifica in $EDITOR",
            "page.terminal.handOffSaved": "Riportata dall’editor",
            "page.terminal.handOffStatus": "L’editor è terminato con lo stato",
            "page.terminal.handOffUnavailable": "Qui non si possono avviare programmi",
        ],
        "es": [
            "page.terminal.handOffSection": "Otro programa · \\.handOffTerminal",
            "page.terminal.handOffExplain": "La app cede el terminal a otro programa, aquí tu $VISUAL o $EDITOR (vi si no hay ninguno), y lo recupera cuando el programa termina. Mientras se ejecuta, ⌃C y ⌃Z son suyos.",
            "page.terminal.handOffNote": "Nota",
            "page.terminal.handOffDefault": "Edítame, guarda y sal del editor.",
            "page.terminal.handOffEdit": "Editar en $EDITOR",
            "page.terminal.handOffSaved": "Traída de vuelta del editor",
            "page.terminal.handOffStatus": "El editor terminó con el estado",
            "page.terminal.handOffUnavailable": "Aquí no se pueden iniciar programas",
        ],
        "zh": [
            "page.terminal.handOffSection": "另一个程序 · \\.handOffTerminal",
            "page.terminal.handOffExplain": "应用把终端交给另一个程序（这里是你的 $VISUAL 或 $EDITOR，都未设置时用 vi），程序结束后再收回。程序运行期间，⌃C 和 ⌃Z 归它所有。",
            "page.terminal.handOffNote": "笔记",
            "page.terminal.handOffDefault": "编辑我，保存，然后退出编辑器。",
            "page.terminal.handOffEdit": "在 $EDITOR 中编辑",
            "page.terminal.handOffSaved": "已从编辑器取回",
            "page.terminal.handOffStatus": "编辑器的退出状态为",
            "page.terminal.handOffUnavailable": "此处无法启动程序",
        ],
        "ja": [
            "page.terminal.handOffSection": "別のプログラム · \\.handOffTerminal",
            "page.terminal.handOffExplain": "アプリは端末を別のプログラム（ここでは $VISUAL か $EDITOR、どちらもなければ vi）に渡し、プログラムが終わると取り戻します。実行中の ⌃C と ⌃Z はそのプログラムのものです。",
            "page.terminal.handOffNote": "メモ",
            "page.terminal.handOffDefault": "編集して保存し、エディタを終了してください。",
            "page.terminal.handOffEdit": "$EDITOR で編集",
            "page.terminal.handOffSaved": "エディタから戻しました",
            "page.terminal.handOffStatus": "エディタの終了ステータス",
            "page.terminal.handOffUnavailable": "ここではプログラムを起動できません",
        ],
    ]
}

// swiftlint:enable line_length
