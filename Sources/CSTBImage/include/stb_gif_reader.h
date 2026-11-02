// A GIF's frames one at a time, out of stb_image's decoder.
//
// stbi_load_gif_from_memory holds every composited frame at full size in one
// allocation, 400 MB for 100 frames of 1000 x 1000. This reads them as its loop
// does and hands each one over, holding the two frames GIF's "restore to
// previous" disposal needs and nothing else.

#ifndef STB_GIF_READER_H
#define STB_GIF_READER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct stb_gif_reader stb_gif_reader;

// A reader of the `length` bytes at `bytes`, which must outlive it, or NULL
// where they are not a GIF or memory runs out.
stb_gif_reader *stb_gif_reader_open(const unsigned char *bytes, int length);

// The next frame, composited, as straight-alpha RGBA of width x height x 4
// bytes, valid until the next call, or NULL after the last. Its delay goes to
// `delay_milliseconds`, its size to `width` and `height`.
const unsigned char *stb_gif_reader_next(stb_gif_reader *reader, int *delay_milliseconds, int *width, int *height);

void stb_gif_reader_close(stb_gif_reader *reader);

#ifdef __cplusplus
}
#endif

#endif
