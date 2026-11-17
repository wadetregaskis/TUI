//  🖥️ TUI — A Terminal UI framework for Swift
//  Controls.swift
//
//  Perf cases: grids, forms, focus traversal, the value controls (stepper,
//  slider, date picker) and menus. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // grid-scroll / grid-edit: a `Grid` of n rows in a scroll view, scrolled (never to its end, at n or 2n), and its
    //   middle row edited. A grid is eager (every row laid out), so `linear`; what an edit of one row rebuilds is the
    //   question. (Scrolled to its end at n and not at 2n, as `wheel:+5*10` over 100 rows was, it broke `linear`.)
    // form-grouped-tab / form-columns-tab: a form of the value controls and a toggle per row, Tab walked through 10
    //   controls and one toggled, in both styles: a focus move must cost the controls it moves between.
    // focus-tab-200 / focus-tab-scaling: Tab through 200 buttons in a scroll view, the page scrolling to follow, to
    //   the last and never round to the first. Not rerun (`-`): at 2n it cost the check about 40 s, debug, for the
    //   class focus-tab-scaling checks over 150 buttons at a third of the price. `linear`: the stack is eager.
    // values-stepper / values-slider / values-date: each value control driven by its keys, alone on the page.
    // form-slider: the slider moved in a form of 5 toggles (50 at 10n): a value change must not rebuild them.
    // menu-walk: a menu of 40 items opened, walked and closed. `linear`: a menu's items are made when it opens.
    static let controls = CaseTableSource(file: #fileID, line: #line, """
        id                 composition   in     size    n    script                                      scales  timed  tags
        grid-scroll        grid          title  80x24   120  open;wheel:+3*5                             linear  -      grid,scroll
        grid-edit          grid          title  80x24   60   open;edit:mid*5                             linear  -      grid,invalidate
        form-grouped-tab   form.grouped  alone  80x24   10   open;key:tab*10;key:space                   flat    t      form,focus
        form-columns-tab   form.columns  alone  120x40  10   open;key:tab*10;key:space                   flat    -      form,focus
        focus-tab-200      controls      title  80x24   200  open;key:tab*199                            -       -      focus,scroll
        focus-tab-scaling  controls      title  80x24   150  open;key:tab*50                             linear  -      focus,scroll
        values-stepper     values        alone  80x24   1    open;key:right*10;key:left*5                flat    -      values
        values-slider      values        alone  80x24   1    open;key:tab;key:right*20;key:left*5        flat    -      values
        values-date        values        alone  80x24   1    open;key:tab*2;key:up*5;key:right;key:up*3  flat    -      values
        form-slider        form.grouped  alone  80x24   5    open;key:tab;key:right*10                   flat    -      form,values,invalidate
        menu-walk          menu          alone  80x24   40   open;key:space;key:down*20;key:esc          linear  -      menu
        """)
}
