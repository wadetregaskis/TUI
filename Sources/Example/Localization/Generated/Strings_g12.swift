// swiftlint:disable line_length
//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g12.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment (group 12): the multi-line editor's own key legend —
//  readline's bindings, which are written on nothing and so have to be written
//  down — and the user-resizable demo, whose gesture is likewise invisible
//  until something says it is there. Its own fragment because group 7 had
//  reached the file-length limit.
//  English is the source of truth; other languages fall back to English (then
//  the key) for anything they omit. Merged into the shared lookup alongside the
//  other fragments.

extension ExampleStrings {
    static let g12: [String: [String: String]] = [
        "en": [
            "page.layout.resizableSection": "Resize it yourself (.userResizable)",
            "page.layout.resizableHint": "Tab to the box, then ←/→ and ↑/↓ to resize it (⇧ for five, ↖/↘ for the limits, ⎋ to give the size back). Or drag an edge — the heavier lines mark the live ones, and the corner takes both at once when both are. Bounded here to 12…40 by 3…8.",
            "page.layout.resizableBody": "Drag my edge, or use the arrows",
            "page.layout.resizableWidth": "Width resizable",
            "page.layout.resizableHeight": "Height resizable",
            "demo.selectionEnabled": "Selection enabled",
            "page.textInput.editorKeysSection": "Editor shortcuts (readline)",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] Back / forward a character · [⌃P] [⌃N] Previous / next line",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] Start / end of line · [⌃T] Transpose · [⌃O] Open a line below",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] Back / forward a word · [⌥⌫] [⌥⌦] Delete a word · [⌥⇥] A literal tab",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] Kill to end / start of line · [⌃Y] Yank it back · [⌃D] Delete forward",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] Select all",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] Undo · [⌃C] [⌃X] Copy / cut the selection",
        ],
        "de": [
            "page.layout.resizableSection": "Selbst anpassen (.userResizable)",
            "page.layout.resizableHint": "Mit Tab zum Kasten, dann ←/→ und ↑/↓ zum Ändern (⇧ für fünf, ↖/↘ für die Grenzen, ⎋ gibt die Größe zurück). Oder eine Kante ziehen — die kräftigeren Linien markieren die aktiven, und die Ecke ändert beides zugleich, wenn beides aktiv ist. Hier begrenzt auf 12…40 mal 3…8.",
            "page.layout.resizableBody": "Zieh an meiner Kante oder nimm die Pfeile",
            "page.layout.resizableWidth": "Breite änderbar",
            "page.layout.resizableHeight": "Höhe änderbar",
            "demo.selectionEnabled": "Auswahl aktiviert",
            "page.textInput.editorKeysSection": "Editor-Kürzel (readline)",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] Ein Zeichen zurück / vor · [⌃P] [⌃N] Vorige / nächste Zeile",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] Zeilenanfang / -ende · [⌃T] Zeichen tauschen · [⌃O] Zeile darunter öffnen",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] Ein Wort zurück / vor · [⌥⌫] [⌥⌦] Wort löschen · [⌥⇥] Echter Tabulator",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] Bis Zeilenende / -anfang löschen · [⌃Y] Wieder einfügen · [⌃D] Vorwärts löschen",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] Alles auswählen",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] Widerrufen · [⌃C] [⌃X] Auswahl kopieren / ausschneiden",
        ],
        "fr": [
            "page.layout.resizableSection": "À redimensionner soi-même (.userResizable)",
            "page.layout.resizableHint": "Tab jusqu'au cadre, puis ←/→ et ↑/↓ pour le redimensionner (⇧ pour cinq, ↖/↘ pour les limites, ⎋ rend la taille). Ou faites glisser un bord — les traits plus épais marquent ceux qui répondent, et le coin agit sur les deux à la fois quand les deux le sont. Borné ici à 12…40 sur 3…8.",
            "page.layout.resizableBody": "Tirez mon bord, ou utilisez les flèches",
            "page.layout.resizableWidth": "Largeur ajustable",
            "page.layout.resizableHeight": "Hauteur ajustable",
            "demo.selectionEnabled": "Sélection activée",
            "page.textInput.editorKeysSection": "Raccourcis de l'éditeur (readline)",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] Caractère précédent / suivant · [⌃P] [⌃N] Ligne précédente / suivante",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] Début / fin de ligne · [⌃T] Transposer · [⌃O] Ouvrir une ligne dessous",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] Mot précédent / suivant · [⌥⌫] [⌥⌦] Supprimer un mot · [⌥⇥] Tabulation littérale",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] Supprimer jusqu'à la fin / au début de la ligne · [⌃Y] Recoller · [⌃D] Supprimer en avant",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] Tout sélectionner",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] Annuler · [⌃C] [⌃X] Copier / couper la sélection",
        ],
        "it": [
            "page.layout.resizableSection": "Ridimensionalo tu (.userResizable)",
            "page.layout.resizableHint": "Tab fino al riquadro, poi ←/→ e ↑/↓ per ridimensionarlo (⇧ per cinque, ↖/↘ per i limiti, ⎋ restituisce la dimensione). Oppure trascina un bordo — le linee più marcate segnano quelli attivi, e l'angolo agisce su entrambi insieme quando entrambi lo sono. Qui limitato a 12…40 per 3…8.",
            "page.layout.resizableBody": "Trascina il mio bordo, o usa le frecce",
            "page.layout.resizableWidth": "Larghezza ridimensionabile",
            "page.layout.resizableHeight": "Altezza ridimensionabile",
            "demo.selectionEnabled": "Selezione attiva",
            "page.textInput.editorKeysSection": "Scorciatoie dell'editor (readline)",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] Un carattere indietro / avanti · [⌃P] [⌃N] Riga precedente / successiva",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] Inizio / fine riga · [⌃T] Scambia caratteri · [⌃O] Apri una riga sotto",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] Una parola indietro / avanti · [⌥⌫] [⌥⌦] Elimina una parola · [⌥⇥] Tabulazione vera",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] Elimina fino a fine / inizio riga · [⌃Y] Reincolla · [⌃D] Elimina in avanti",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] Seleziona tutto",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] Annulla · [⌃C] [⌃X] Copia / taglia la selezione",
        ],
        "es": [
            "page.layout.resizableSection": "Cámbialo tú (.userResizable)",
            "page.layout.resizableHint": "Tab hasta el recuadro y luego ←/→ y ↑/↓ para redimensionarlo (⇧ para cinco, ↖/↘ para los límites, ⎋ devuelve el tamaño). O arrastra un borde — las líneas más gruesas marcan los activos, y la esquina mueve ambos a la vez cuando ambos lo están. Aquí limitado a 12…40 por 3…8.",
            "page.layout.resizableBody": "Arrastra mi borde, o usa las flechas",
            "page.layout.resizableWidth": "Ancho ajustable",
            "page.layout.resizableHeight": "Alto ajustable",
            "demo.selectionEnabled": "Selección activada",
            "page.textInput.editorKeysSection": "Atajos del editor (readline)",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] Un carácter atrás / adelante · [⌃P] [⌃N] Línea anterior / siguiente",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] Inicio / fin de línea · [⌃T] Transponer · [⌃O] Abrir una línea debajo",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] Una palabra atrás / adelante · [⌥⌫] [⌥⌦] Borrar una palabra · [⌥⇥] Tabulador literal",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] Borrar hasta el final / el principio de la línea · [⌃Y] Volver a pegar · [⌃D] Borrar hacia delante",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] Seleccionar todo",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] Deshacer · [⌃C] [⌃X] Copiar / cortar la selección",
        ],
        "zh": [
            "page.layout.resizableSection": "自己调整大小 (.userResizable)",
            "page.layout.resizableHint": "用 Tab 移到方框，再用 ←/→ 和 ↑/↓ 调整大小（⇧ 一次五格，↖/↘ 到上下限，⎋ 交还尺寸）。也可以拖动边框 —— 较粗的线标出可拖动的边；两个方向都可调整时，拐角会同时改变两者。此处限制为 12…40 乘 3…8。",
            "page.layout.resizableBody": "拖我的边，或用方向键",
            "page.layout.resizableWidth": "可调宽度",
            "page.layout.resizableHeight": "可调高度",
            "demo.selectionEnabled": "启用选择",
            "page.textInput.editorKeysSection": "编辑器快捷键（readline）",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] 前后移动一个字符 · [⌃P] [⌃N] 上一行 / 下一行",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] 行首 / 行尾 · [⌃T] 交换字符 · [⌃O] 在下方新开一行",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] 前后移动一个词 · [⌥⌫] [⌥⌦] 删除一个词 · [⌥⇥] 输入真正的制表符",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] 删到行尾 / 行首 · [⌃Y] 粘回来 · [⌃D] 向后删除",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] 全选",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] 撤销 · [⌃C] [⌃X] 拷贝 / 剪切所选内容",
        ],
        "ja": [
            "page.layout.resizableSection": "自分でリサイズ (.userResizable)",
            "page.layout.resizableHint": "Tab で枠に移り、←/→ と ↑/↓ でサイズを変えます（⇧ で 5 セル、↖/↘ で上下限、⎋ でサイズを返す）。辺をドラッグしても構いません — 太い線が動く辺の印で、両方が有効なときは角が両方を同時に変えます。ここでは 12…40 × 3…8 に制限しています。",
            "page.layout.resizableBody": "辺をドラッグするか、矢印キーで",
            "page.layout.resizableWidth": "幅を変更可",
            "page.layout.resizableHeight": "高さを変更可",
            "demo.selectionEnabled": "選択を有効にする",
            "page.textInput.editorKeysSection": "エディタのショートカット（readline）",
            "page.textInput.editorKeys.motion": "[⌃B] [⌃F] 一文字戻る／進む · [⌃P] [⌃N] 前の行／次の行",
            "page.textInput.editorKeys.lineEnds": "[⌃A] [⌃E] 行頭／行末 · [⌃T] 文字を入れ替え · [⌃O] 下に行を開く",
            "page.textInput.editorKeys.words": "[⌥B] [⌥F] 一語戻る／進む · [⌥⌫] [⌥⌦] 一語削除 · [⌥⇥] 本物のタブ",
            "page.textInput.editorKeys.kill": "[⌃K] [⌃U] 行末 / 行頭まで削除 · [⌃Y] 貼り戻す · [⌃D] 前方削除",
            "page.textInput.editorKeys.selectAll": "[⌃⌥A] すべて選択",
            "page.textInput.editorKeys.undoClipboard": "[⌃Z] 取り消す · [⌃C] [⌃X] 選択部分をコピー／カット",
        ],
    ]
}
// swiftlint:enable line_length
