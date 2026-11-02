// Counts every allocation a process makes, and writes the count at exit.
//
//   clang -dynamiclib -O2 -o alloc_count.dylib alloc_count.c
//   DYLD_INSERT_LIBRARIES=$PWD/alloc_count.dylib ALLOC_COUNT_FILE=/tmp/n ./Stress --session inbox
//
// A count of work, so two builds or two settings can be compared on a machine too
// busy for timings to mean anything. macOS only; the build products here are ad hoc
// signed, which `DYLD_INSERT_LIBRARIES` accepts. No output without ALLOC_COUNT_FILE.
#include <malloc/malloc.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static atomic_ullong count;

#define DYLD_INTERPOSE(replacement, replacee)                                            \
    __attribute__((used)) static struct {                                                \
        const void *r;                                                                   \
        const void *e;                                                                   \
    } interpose_##replacee __attribute__((section("__DATA,__interpose"))) = {            \
        (const void *)(unsigned long)&replacement, (const void *)(unsigned long)&replacee}

static void *counted_malloc(size_t size) {
    atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    return malloc(size);
}
static void *counted_calloc(size_t n, size_t size) {
    atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    return calloc(n, size);
}
static void *counted_realloc(void *p, size_t size) {
    atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    return realloc(p, size);
}
static int counted_memalign(void **out, size_t alignment, size_t size) {
    atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    return posix_memalign(out, alignment, size);
}
static void *counted_zone_malloc(malloc_zone_t *zone, size_t size) {
    atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    return malloc_zone_malloc(zone, size);
}
DYLD_INTERPOSE(counted_malloc, malloc);
DYLD_INTERPOSE(counted_calloc, calloc);
DYLD_INTERPOSE(counted_realloc, realloc);
DYLD_INTERPOSE(counted_memalign, posix_memalign);
DYLD_INTERPOSE(counted_zone_malloc, malloc_zone_malloc);

__attribute__((destructor)) static void report(void) {
    const char *path = getenv("ALLOC_COUNT_FILE");
    if (!path) return;
    FILE *file = fopen(path, "w");
    if (!file) return;
    fprintf(file, "%llu\n", atomic_load(&count));
    fclose(file);
}
