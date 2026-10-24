//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_gUndo.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the names of the Example's own undo steps — a
//  list's or table's move and delete, a drop, a cleared cell — which the Edit
//  menu shows as "Undo Move". English is the source of truth; every other
//  language carries the same key set. Named rather than numbered, as
//  `gFiles` is, so a parallel lane's next numbered group does not collide.

extension ExampleStrings {
    static let gUndo: [String: [String: String]] = [
        "en": [
            "undo.action.move": "Move",
            "undo.action.delete": "Delete",
            "undo.action.copy": "Copy",
            "undo.action.discard": "Discard",
            "undo.action.reset": "Reset",
        ],
        "de": [
            "undo.action.move": "Verschieben",
            "undo.action.delete": "Löschen",
            "undo.action.copy": "Kopieren",
            "undo.action.discard": "Verwerfen",
            "undo.action.reset": "Zurücksetzen",
        ],
        "fr": [
            "undo.action.move": "Déplacer",
            "undo.action.delete": "Supprimer",
            "undo.action.copy": "Copier",
            "undo.action.discard": "Jeter",
            "undo.action.reset": "Réinitialiser",
        ],
        "it": [
            "undo.action.move": "Sposta",
            "undo.action.delete": "Elimina",
            "undo.action.copy": "Copia",
            "undo.action.discard": "Scarta",
            "undo.action.reset": "Reimposta",
        ],
        "es": [
            "undo.action.move": "Mover",
            "undo.action.delete": "Eliminar",
            "undo.action.copy": "Copiar",
            "undo.action.discard": "Descartar",
            "undo.action.reset": "Restablecer",
        ],
        "zh": [
            "undo.action.move": "移动",
            "undo.action.delete": "删除",
            "undo.action.copy": "拷贝",
            "undo.action.discard": "丢弃",
            "undo.action.reset": "重置",
        ],
        "ja": [
            "undo.action.move": "移動",
            "undo.action.delete": "削除",
            "undo.action.copy": "コピー",
            "undo.action.discard": "破棄",
            "undo.action.reset": "リセット",
        ],
    ]
}
