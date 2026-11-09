// Replacement for the UBSan runtime (not available in the WASI sysroot).
// Compiled as a second translation unit so user line numbers are untouched.
// On the first violation we print a machine-readable marker to stderr and exit(97).
export const UB_HANDLERS = `
#include <stdio.h>
#include <stdlib.h>
extern "C" {
struct SrcLoc { const char* file; unsigned line; unsigned col; };
struct Data { SrcLoc loc; };
static void die(const Data* d, const char* kind) {
  fprintf(stderr, "\\x01UB|%u|%u|%s\\n", d->loc.line, d->loc.col, kind);
  fflush(stderr);
  _Exit(97);
}
#define H2(name, kind) \\
  void __ubsan_handle_##name(Data* d, unsigned long, unsigned long) { die(d, kind); } \\
  void __ubsan_handle_##name##_abort(Data* d, unsigned long, unsigned long) { die(d, kind); }
#define H1(name, kind) \\
  void __ubsan_handle_##name(Data* d, unsigned long) { die(d, kind); } \\
  void __ubsan_handle_##name##_abort(Data* d, unsigned long) { die(d, kind); }
H2(add_overflow, "add")
H2(sub_overflow, "sub")
H2(mul_overflow, "mul")
H2(divrem_overflow, "div")
H2(shift_out_of_bounds, "shift")
H1(negate_overflow, "neg")
H1(out_of_bounds, "index")
}
`;
