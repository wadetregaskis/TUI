//  🖥️ TUI — A Terminal UI framework for Swift
//  CWASIStack.h
//
//  Created by Wade Tregaskis
//  License: MIT

#ifndef CWASISTACK_H
#define CWASISTACK_H

#include <stdint.h>

// The bounds of WebAssembly's stack, for `StackGuard` (TUICore).
//
// On wasm32 the C stack Swift's frames live on is a region of linear memory
// the linker lays out (`wasm-ld -z stack-size=…`), growing down from
// `__stack_high` towards `__stack_low`, with the program's data below it and
// no guard page between: a stack that runs out writes over the data. The
// linker defines both symbols, and only C can take a linker symbol's address,
// which is what this shim is for. Only TUICore's WebAssembly build depends on
// it, so on every other platform it is never built.

#if defined(__wasm__)
/// The lowest address the stack may reach: its end, as it grows down.
uintptr_t tui_wasm_stack_low(void);
/// The address the stack starts at, one past its highest byte.
uintptr_t tui_wasm_stack_high(void);
#endif

#endif
