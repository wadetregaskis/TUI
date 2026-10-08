//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormControlRow.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Row-kind markers

/// A self-labelled control that a ``Form`` places in the control column with its
/// own clickable label (a checkbox/radio), rather than pulling a label to the
/// pillar. Conformed by ``Toggle`` and ``RadioButtonGroup``.
protocol FormControlRow {}

extension Toggle: FormControlRow {}
