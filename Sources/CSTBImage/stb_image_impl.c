// stb_image implementation file
// This activates the implementation of stb_image.h (single-header library).
// Public domain / MIT license - see stb_image.h for details.

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// A GIF's frames one at a time (stb_gif_reader.h).

#include "stb_gif_reader.h"

struct stb_gif_reader {
   stbi__context context;
   stbi__gif gif;
   // Copies of the last two frames. `two_back` is what stbi__gif_load_next
   // restores a "restore to previous" frame's pixels from: the frame before
   // last, as stbi__load_gif_main hands it.
   stbi_uc *last;
   stbi_uc *two_back;
   int frames;
};

stb_gif_reader *stb_gif_reader_open(const unsigned char *bytes, int length)
{
   stb_gif_reader *reader = (stb_gif_reader *) STBI_MALLOC(sizeof(stb_gif_reader));
   if (!reader) return NULL;
   memset(reader, 0, sizeof(*reader));
   stbi__start_mem(&reader->context, bytes, length);
   if (!stbi__gif_test(&reader->context)) {
      STBI_FREE(reader);
      return NULL;
   }
   return reader;
}

const unsigned char *stb_gif_reader_next(stb_gif_reader *reader, int *delay_milliseconds, int *width, int *height)
{
   int components = 0;
   stbi_uc *frame = stbi__gif_load_next(
      &reader->context, &reader->gif, &components, 4, reader->frames >= 2 ? reader->two_back : NULL);
   // The end's marker, which is the context itself, or an error: no more frames.
   if (!frame || frame == (stbi_uc *) &reader->context) return NULL;

   size_t size = (size_t) reader->gif.w * (size_t) reader->gif.h * 4;
   // The two copies trade places, so the older is the one written over.
   stbi_uc *oldest = reader->two_back;
   reader->two_back = reader->last;
   reader->last = oldest ? oldest : (stbi_uc *) STBI_MALLOC(size);
   if (!reader->last) return NULL;
   memcpy(reader->last, frame, size);
   reader->frames += 1;
   // What a "clear" frame clears to. stb_image keeps the picture from before
   // the frame, which undoes it rather than clearing it, and leaves behind what
   // a frame of another disposal drew underneath. A browser clears to nothing.
   memset(reader->gif.background, 0, size);

   *delay_milliseconds = reader->gif.delay;
   *width = reader->gif.w;
   *height = reader->gif.h;
   return frame;
}

void stb_gif_reader_close(stb_gif_reader *reader)
{
   STBI_FREE(reader->gif.out);
   STBI_FREE(reader->gif.history);
   STBI_FREE(reader->gif.background);
   STBI_FREE(reader->last);
   STBI_FREE(reader->two_back);
   STBI_FREE(reader);
}
