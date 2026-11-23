/* Demo program for trying out dap-memview.
 *
 * Build (macOS/clang, debug info required):
 *   clang -g -O0 -o demo demo.c
 *
 * Then in nvim: start a codelldb session on ./demo, break inside the loop,
 * and run `:DapMemView buf` — step with F10 and watch bytes change.
 * `:DapMemView msg` views what the pointer points at (buf+32).
 * `:DapMemView rec` shows a struct: 4 bytes of id, 4 of padding, then a
 * pointer — put the cursor on its 8 bytes and press <CR> to follow it to
 * `counter`, <BS> to come back.
 */
#include <stdio.h>
#include <string.h>

struct record {
  int id;
  int *id_ptr;
};

int main(void) {
  char buf[64];
  memset(buf, 0, sizeof buf);
  strcpy(buf, "watch this buffer mutate");
  char *msg = buf + 32;
  int counter = 7;
  struct record rec = {42, &counter};

  for (int i = 0; i < 26; i++) {
    buf[32 + (i % 16)] = (char)('a' + i); /* breakpoint here */
    printf("iteration %d: %s (record %d -> %d)\n", i, msg, rec.id, *rec.id_ptr);
  }
  return 0;
}
