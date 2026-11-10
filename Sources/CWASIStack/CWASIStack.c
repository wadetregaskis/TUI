//  🖥️ TUI — A Terminal UI framework for Swift
//  CWASIStack.c
//
//  Created by Wade Tregaskis
//  License: MIT

#include "CWASIStack.h"

#if defined(__wasm__)
// Symbols `wasm-ld` defines (LLVM 16 and later): the addresses are the
// values; there is no object at either.
extern char __stack_low;
extern char __stack_high;

uintptr_t tui_wasm_stack_low(void) { return (uintptr_t)&__stack_low; }
uintptr_t tui_wasm_stack_high(void) { return (uintptr_t)&__stack_high; }
#endif
