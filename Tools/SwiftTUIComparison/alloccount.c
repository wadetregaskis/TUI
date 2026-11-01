// Interposes the malloc family and keeps counts in a file the driver maps. Loaded with DYLD_INSERT_LIBRARIES.
#include <fcntl.h>
#include <malloc/malloc.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
typedef struct { _Atomic uint64_t allocs, frees, bytes; } Counters;
static Counters fallback;
static Counters *c = &fallback;
__attribute__((constructor)) static void setup(void) {
    const char *path = getenv("ALLOC_COUNT_FILE");
    if (!path) return;
    int fd = open(path, O_RDWR | O_CREAT, 0644);
    if (fd < 0) return;
    ftruncate(fd, 4096);
    void *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p != MAP_FAILED) c = p;
    close(fd);
}
#define NOTE(n) do { atomic_fetch_add_explicit(&c->allocs, 1, memory_order_relaxed); atomic_fetch_add_explicit(&c->bytes, (n), memory_order_relaxed); } while (0)
static void *my_malloc(size_t n) { NOTE(n); return malloc(n); }
static void *my_calloc(size_t a, size_t b) { NOTE(a * b); return calloc(a, b); }
static void *my_realloc(void *p, size_t n) { NOTE(n); return realloc(p, n); }
static void my_free(void *p) { if (p) atomic_fetch_add_explicit(&c->frees, 1, memory_order_relaxed); free(p); }
static int my_posix_memalign(void **r, size_t a, size_t n) { NOTE(n); return posix_memalign(r, a, n); }
static void *my_zone_malloc(malloc_zone_t *z, size_t n) { NOTE(n); return malloc_zone_malloc(z, n); }
static void *my_zone_memalign(malloc_zone_t *z, size_t a, size_t n) { NOTE(n); return malloc_zone_memalign(z, a, n); }
#define I(a, b) __attribute__((used, section("__DATA,__interpose"))) static struct { const void *r, *o; } in_##b = { (const void *)a, (const void *)b };
I(my_malloc, malloc) I(my_calloc, calloc) I(my_realloc, realloc) I(my_free, free) I(my_posix_memalign, posix_memalign)
I(my_zone_malloc, malloc_zone_malloc) I(my_zone_memalign, malloc_zone_memalign)
