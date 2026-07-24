/* Demo program for trying out dap-memview.
 *
 * Build (macOS/clang, debug info required):
 *   clang -g -O0 -o demo demo.c
 *
 * Then in nvim: start a codelldb session on ./demo, break inside the loop,
 * and run `:DapMemView buf` — step with F10 and watch bytes change.
 */
#include <stdio.h>
#include <string.h>

int main(void) {
  char buf[64];
  memset(buf, 0, sizeof buf);
  strcpy(buf, "watch this buffer mutate");

  for (int i = 0; i < 26; i++) {
    buf[32 + (i % 16)] = (char)('a' + i); /* breakpoint here */
    printf("iteration %d: %s\n", i, buf + 32);
  }
  return 0;
}
