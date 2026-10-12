# OS-9 compatibility design

*Written with assistance from Claude (Anthropic); research, analysis and text by Claude, design
decisions and review by CD-i Fan <cdifan@gmail.com>.*

How this toolchain (`m68k-elfos9`, the GCC/binutils/newlib fork used for CD-i and OS-9/68000
development) interoperates with code and libraries built by Microware's own compilers: the
calling convention Microware's compilers use and how GCC follows it, the conversion between
Microware's object format (ROF) and ELF, the drop-ins for Microware's tools, and how all of it is
tested. The tools' own documents, in the [m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools)
repository, give their usage and details; this document gives the design and its reasons.

Contents:

1. [Current toolchain](#1-current-toolchain)
2. [The GCC fork vs. mainline](#2-the-gcc-fork-vs-mainline)
3. [Microware C calling convention](#3-microware-c-calling-convention)
4. [`-mos9call` design](#4--mos9call-design)
5. [How dependent is the toolchain on ELF?](#5-how-dependent-is-the-toolchain-on-elf)
6. [ROF interoperability: `rof2elf` and `elf2rof`](#6-rof-interoperability-rof2elf-and-elf2rof)
7. [Microware tools used for testing](#7-microware-tools-used-for-testing)
8. [Build and host environments](#8-build-and-host-environments)
9. [Running tests on OS-9: `cdirun`](#9-running-tests-on-os-9-cdirun)
10. [Licensing and upstreaming](#10-licensing-and-upstreaming)
11. [Tests](#11-tests)
12. [Open questions](#12-open-questions)
13. [References](#13-references)

---

## 1. Current toolchain

The [`Dockerfile`](Dockerfile) builds, from the pinned submodules under `src/`:

| Component | Source | Notes |
|---|---|---|
| binutils 2.35 | [cdifan/binutils-gdb](https://github.com/cdifan/binutils-gdb) `m68k-gas-fixes` | upstream 2.35 with four gas fixes (§2); the target name is accepted through generic m68k patterns |
| GCC 11.1.0 | [cdifan/gcc](https://github.com/cdifan/gcc) `11.1.0-os9-compat` (Murachue's `11.1.0-os9` plus this work) | `-mpcrel`, `-ma6rel`, `-mbsrw` (§2), and the OS-9 options (§4) |
| newlib 4.1.0 | [cdifan/newlib-cygwin](https://github.com/cdifan/newlib-cygwin) `newlib-4.1.0-os9-compat` | multilibs for both conventions, and an OS-9 runtime in libgloss (§4) |
| m68k-os9-tools | [cdifan/m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools) `main-compat` | a heavily extended fork of Murachue's elf2mod: `elf2mod` (linked ELF → OS-9 module), `rof2elf`, `elf2rof` (§6), and the drop-ins for Microware's tools |
| psximager | [murachue/psximager](https://github.com/murachue/psximager) `cdi` | disc images |

Build flow for an application:

```
gcc -mpcrel -ma6rel  →  as (ELF .o)  →  ld -q -T os9.ld (ELF, .data at -0x8000)  →  elf2mod  →  OS-9 module
```

`m68k-os9-gcc` does all of it in one step, with newlib's OS-9 runtime (§4, "Libraries").

The OS-9 data model: code is position independent (PC-relative), and global data is addressed
relative to `a6`, which points 0x8000 bytes past the start of the static storage area. a5 is the
frame pointer when one is used (code built with `-fomit-frame-pointer`, such as newlib, has none).

## 2. The GCC fork vs. mainline

Murachue's `11.1.0-os9` branch is **9 commits on top of the `releases/gcc-11.1.0` tag** (commit
`50bc918`):

```
053e3cae1 static const struct[][] in a function was become a6rel but should be pcrel
c68a391d2 SYMBOL_REF_DECL for LABEL_REF is wrong, and LABEL_REF never points data so decl==NULL is ok
186b55267 HACK: use adjust_address_nv for XFmode to avoid assertion fail on compiling libgcc:mulxc3/divxc3
2f07cfbd6 don't a6rel on rodata that will be meld to .text
6a48ce2d1 a6rel-able rtx may be const-of-plus-of-sym-and-constint
79f1fa700 a5 is usable when -mpcrel
ce888142f target m68k-*-elfos9 for binutils
c77e9d47a -ma6rel uses %a6 for var_decls
4aa5c8071 -mbsrw use bsr.w for inter-function call
50bc9185c c++: Remove #error for release builds        <- releases/gcc-11.1.0
```

Total: 7 files changed, 89 insertions, 15 deletions (`gcc/config.gcc`, and in
`gcc/config/m68k/`: `m68k-os9.h`, `m68k.c`, `m68k.h`, `m68k.md`, `m68k.opt`, `predicates.md`).

To get this history into the shallow submodule:

```sh
git -C src/gcc fetch --depth 1 origin 50bc9185c2821350f0b785d6e23a6e9dcde58466
git -C src/gcc tag gcc-11.1.0-base 50bc9185c2821350f0b785d6e23a6e9dcde58466
git -C src/gcc fetch --depth=10 origin 053e3cae1ce30de60a7e1f91421a00cb41670849
git -C src/gcc diff --stat gcc-11.1.0-base HEAD
```

### Portability to current mainline (GCC 17)

Murachue's fork diff, applied as a dry run to gcc-mirror `master` (`BASE-VER` 17.0.0):

- After mapping `m68k.c` → `m68k.cc` (renamed in GCC 12), every hunk applies, only at shifted
  line numbers. That covers `-mbsrw`, `-ma6rel` (including the `sym(%a6)` output in
  `print_operand_address`), the a6 reservation in `m68k_conditional_register_usage`, and the
  `adjust_address_nv` hack.
- The one rejected hunk (`predicates.md`) only adds a comment.
- **Must fix:** `dbxelf.h` no longer exists (stabs support was removed in GCC 13), so it has to
  be dropped from the `m68k-*-elfos9*` `tm_file` line in `config.gcc`.
- **Watch:** m68k still defaults to the old register allocator ("reload") in master, with LRA
  behind the undocumented `-mlra`. If reload is removed, `-ma6rel`/`-mpcrel` need retesting
  under LRA.
- The cc0 removal in GCC 12 rewrote m68k condition-code handling, but none of the fork's commits
  touch that area.

The argument-passing hooks (`function_arg_info`) are the same from GCC 10 through 17, so this
work's `-mos9call` (§4) would port nearly unchanged. It is implemented on GCC 11.1, the fork's
baseline; a port to GCC 17 is a separate step (§12).

## 3. Microware C calling convention

### What the manual says

*OS-9 C Language User Manual* (Microware C compiler 3.1, 1991), chapter 3, "Compiler
Organization":

- **Registers:** d0–d1 for arguments and return values; d2–d3 and a0–a1 for compiler
  temporaries; d4–d7 and a2–a4 for register variables. a5 is the frame pointer, a6 the base of
  static storage (never changed by C code), a7 the stack pointer.
- **Arguments:**
  - The first integral argument (int, long, pointer, or char/short widened to int) goes in d0,
    the second in d1.
  - A double as the first argument goes in d0:d1, most significant half in d0.
  - Remaining arguments are pushed on the stack.
  - If the first argument is integral and the second a double, the double goes entirely on the
    stack.
- **Floats** are converted to double when passed.
- **Return values:** integral and float values in d0, doubles in d0:d1.
- **Preserved registers:** "All functions … are required to restore any changed registers … The
  only exceptions to this are function return register(s) and register(s) in which the
  function's argument(s) are passed."
- **Stack arguments** are 4-byte longwords. char/short are sign-extended, unsigned char/short
  zero-extended.
- Calls use `bsr`. The linker builds a jump table (`_jmptbl`) for targets beyond ±32K.

### What the compiler actually does

[`test/os9c/testos9c.c`](test/os9c/testos9c.c) is a K&R C probe covering the cases the manual
leaves open. Its header explains the test numbering. It is compiled with two Microware compilers:

| Output | Compiler | Command |
|---|---|---|
| [`testos9c-cc32.a`](test/os9c/testos9c-cc32.a) | **Microware C 3.2**, the original compiler (DOS-hosted cross version, run under vDos) | `xcc -a -s -bp testos9c.c` |
| [`testos9c-ucc25.a`](test/os9c/testos9c-ucc25.a) | **Microware Ultra C 2.5 in K&R compatibility mode** | `xcc -mode=compat -to=osk -tp=68k -a -c -s testos9c.c` |

Microware C 3.2's `-a` output is the compiler pass's (`c68`) output, from before the assembly
optimizer (`o68`) runs: compiling with and without `-o` (optimizer off) gives byte-identical
`.a` files. The calling convention and register-save masks come from `c68`, so the probe shows
the right stage.

Microware C 3.2 is the reference, since the CD-i libraries were built with it. Ultra C 2.5's
compat mode agrees with it on argument passing and most return values. Its column has five
entries: two real differences (float return and struct return, the rows with bold names) and three
harmless ones (restoring d0 in the callee, and registers it additionally saves or relies on).

Observed rules:

| Topic | Microware C 3.2 (reference) | Ultra C 2.5 compat, if different | Tests |
|---|---|---|---|
| Arg 1 | int/pointer → d0, double → d0:d1, struct → stack | | 01, 05, 08, 12 |
| Arg 2 | int/pointer → d1 **only if arg 1 went in d0**, otherwise stack | | 04, 07, 12, 13 |
| Other args | stack, pushed right to left, 4-byte slots; caller pops | | 02, 03 |
| `f(int, double, int)` | int in d0, double and last int on the stack, d1 unused | | 04 |
| `f(struct, int)` | both on the stack, d0 unused | | 12 |
| Structs by value | copied onto the stack (even 20 bytes), no hidden pointer | | 12–15 |
| Odd-sized structs | `sizeof` isn't padded (1, 2, 3, 5, 6, 7), but the stack slot is rounded up to a multiple of 4 bytes, and the struct sits at the *start* (lowest address) of its slot | | 50–62, 80–83 |
| Data layout | a `short`, `int` or `double` after a `char` is aligned to 2 bytes (16-bit alignment), `enum` is 4 bytes, and bitfields are allocated from the most significant bit. GCC's m68k layout is identical (checked with the same tests), so shared structs need no changes | | 70–79 |
| Floats (unprototyped) | promoted to double (`_T$FtoD`): in d0:d1 or 8 bytes on the stack; a callee receives a double | | 10, 11, 32 |
| Indirect calls | same convention as direct calls | | 16 |
| char/short arguments | caller widens, and the callee re-widens | | 09, 33 |
| char/short returns | **caller** widens the result (`ext.w`/`ext.l`); callee leaves it narrow | | 17–19, 34 |
| Pointer return | d0 (not a0) | | 20 |
| **float return** | float in d0: the callee returns it unconverted, and the caller converts it to double (`_T$FtoD`) only when needed, or stores d0 directly into a float | a **double** in d0:d1, K&R-style: the callee converts the result to double, and the caller treats d0:d1 as a double, converting back to float only when storing into a float | 21, 28, 29 |
| double return | d0:d1 | | 22 |
| a0, a1, d2, d3 | callee-saved (observed; a1 in the struct copies of tests 57, 61 and 83). The probe's Microware C 3.2 output never uses d4–d7; the manual says all registers except argument and return registers are preserved | also saves d4–d7 when used | 35, 36, 43–47, 57, 61, 83 |
| d1 (callee) | saved unless it carries an argument or the return value: `void f()` and one-int-arg/int-return functions both restore d1. Exception: a `float`-returning function doesn't restore d1 (`def28` clobbers it in `_T$FMul`), i.e. a float return is treated like a d0:d1 return, so callers can't rely on d1 surviving such a call | | 01, 28, 43, 44 |
| d0 (callee) | **never restored**: functions push d0 in the prologue, to give the first argument a stack slot (its "home slot"), but don't restore it, even in `void f()` | `void f()` saves *and restores* d0 | 43 |
| d1 (caller) | callers **rely** on d1 surviving a call when d1 carries no argument or return value: `keep47` keeps a value in d1 across an int-returning call (`keep40`–`keep42` reload their values from the stack instead) | also relies on d1 in `keep40`–`keep42`, and on pointers in a0/a1 surviving a call in `keep46` (a0 also in `keep47`) | 40–42, 46, 47 |
| **Struct return** | **static buffer**: the callee copies the result into a static (`vsect`) buffer and returns its *address* in d0; the caller copies from there. No hidden pointer is passed, and it isn't reentrant (the "PCC convention", from the old Portable C Compiler) | caller passes a buffer address in **a0** for *all* structs; arguments still use d0/d1; callee copies into `(a0)`, preserves a0, returns nothing in d0 | 24–27 |

So d0 is always caller-saved, while d1 is preserved unless it's used for an argument or the
return value. The two compilers' struct-return conventions are incompatible with each other, and
so are their float-return conventions, so no single scheme can work with both compilers for
functions returning a struct or a `float`.

The struct-return and float-return differences are **undocumented**. *Using Ultra C/C++* (chapter
2, "Compatibility with the Microware K&R C Compiler" and "Differences Between Compatibility Source
Mode and the Microware K&R C Compiler") calls compat mode "logically equivalent" to the K&R
compiler, and lists the known differences:
- `remote` storage class
- keywords as struct member names
- stricter error checking
- name clashes
- the executive
- `csl` vs. `cio`
- K&R vs. `__ansi_*` library functions
- library size
- assembly escapes
- stdio macros with old ROFs

It even implies that Ultra C 2.5 code links with K&R-compiled ROFs, but it says nothing about
calling conventions. In practice, mixing works unless a function returning a struct or a `float`
crosses between the two compilers.

Two earlier GCC ports to OS-9 supported a similar convention, but neither matches it exactly:
- **GCC 1.37.1, by T. Shinohara and A. Seyama** (on the "CDISC 4" CD-i developer disc, 1993):
  the first 8 bytes of *named* arguments go in d0/d1 (`-mregparm`, the default), and unnamed
  arguments always go on the stack, like Ultra C 2.5. It treats d0, d1, a0 and a1 as scratch,
  and returns structs via a pointer in a1. It emits Microware assembler syntax directly.
- **GCC 2.6.2, by Walter Hunt** (`gcc-sun4-os9-2.6.2`): `-mregparm` keeps a0/a1 callee-saved,
  but assigns registers by byte offset, so for `int, double` it splits the double between d1 and
  the stack. Carl Kreider's 1997 patch, taken from Stephan Paschedag's OS-9 port of GCC 2.5.8,
  stops the splitting and keeps structs on the stack, but still assigns by byte offset, so a
  small struct as the first argument would leave the next int in d1.

Both contradict what the Microware compilers actually do in some cases; the design below follows
the observed behaviour.

## 4. `-mos9call` design

A target option of the `m68k-elfos9` GCC, implemented in `gcc/config/m68k/`, and documented with
the other OS-9 options in GCC's manual (m68k options).

### Which functions use it

GCC function types do not record language linkage, so a function pointer cannot know whether
its target is `extern "C"`. The only consistent rule the backend can apply is:

> Under `-mos9call`, every call to, and definition of, a function of plain function type
> (`FUNCTION_TYPE`) uses the OS-9 convention, whatever its linkage. That includes free functions,
> static member functions, `extern "C"` functions, and all calls through plain function pointers.
> Non-static member functions (`METHOD_TYPE`, which take `this`) and compiler-generated library
> calls (libgcc helpers such as `__mulsi3` and soft-float routines) keep the normal stack
> convention.

The backend sees the function type on both sides (call sites, including indirect calls, and the
function being compiled), so this is a simple type check. It needs no name-mangling heuristics.

Further scope rules:

- **C++:** static member functions use the OS-9 convention, since they're ordinary functions.
  Non-static member functions (virtual functions, constructors, destructors, a lambda's
  `operator()`) keep the stack convention. Free functions with C++ linkage use the OS-9 convention
  too: that's unavoidable, because a plain function pointer can't tell them apart from C
  functions, and harmless. The function-pointer conversion of a capture-less lambda has plain
  function type, so such lambdas can serve as callbacks for Microware libraries. The toolchain
  builds C only, so this applies once C++ is enabled (§12).
- **Interrupt handlers:** functions with the `interrupt_handler` (or `interrupt`) attribute are
  always excluded; they keep their own entry and exit conventions.
- **Per-function override:** two attributes allow mixing conventions within one program.
  `__attribute__((stackcall))` forces the stack convention under `-mos9call`, e.g. for runtime
  entry points defined in libgcc or in assembly ("Libraries" below).
  `__attribute__((os9call))` selects the OS-9 convention without the flag, e.g. for declaring
  individual Microware library functions. Both are part of the function type, so they can be
  used in function-pointer declarations and typedefs, and pointers keep the right convention:
  `int (__attribute__((os9call)) *cmp)(const void *, const void *);`. Assigning a function or
  pointer of one convention to a pointer of another is diagnosed as an incompatible pointer type.
  The names are this project's own: GCC has no calling-convention attributes for m68k (only
  `interrupt`, `interrupt_handler` and `interrupt_thread`), and Microware documents none for 68K.
  They're modelled on GCC's x86 attributes. `stackcall` corresponds to x86's `cdecl` (arguments
  on the stack, the *caller* pops them), not to `stdcall`, where the callee pops the arguments
  (on m68k, that would be GCC's `-mrtd` convention).

  **C++ mangling:** GCC's C++ front end already mangles every type attribute that affects type
  identity, as written, as a vendor-extended qualifier (`U7os9call`, `U9stackcall`). To keep one
  mangling per type, the attribute handlers drop the redundant attribute: `os9call` under
  `-mos9call`, and `stackcall` without it. So only an attribute that differs from the flag's
  default appears in mangled names, and mangling depends on the flag: under `-mos9call`,
  stack-convention function types carry `U9stackcall`; without it, `os9call` types carry
  `U7os9call`. Code compiled without `-mos9call` that doesn't use `os9call` mangles exactly as
  with the regular m68k ELF compiler. No changes to the C++ front end are needed.

  Two limits: a function's own convention isn't part of its mangled name (only the types of
  pointer parameters are), so mismatched declarations in different files link silently; and the
  meaning of an unattributed type depends on the flag.

### Arguments

Positional, as observed (§3). Arguments are classified by their *type*, not by GCC's machine
mode: small structs and unions have integer modes in GCC, but they're aggregates and always go
on the stack.

- arg 1: ≤ 4-byte scalar (int, long, pointer, widened char/short, float) → d0; 8-byte scalar
  (double, `long long`) → d0:d1; anything else → stack. That includes aggregates of any size,
  `long double` (12 bytes) and `_Complex` types
- arg 2: ≤ 4-byte scalar → d1, only if arg 1 used d0 alone (not d0:d1, not the stack); otherwise
  stack
- everything else on the stack, pushed right to left, caller pops; no stack space is reserved
  for register arguments
- an aggregate on the stack takes a slot rounded up to a multiple of 4 bytes, and sits at the
  *start* of it (padding after the data). GCC normally right-justifies aggregates smaller than 4
  bytes (a 1-byte struct at offset 3 of its slot, a 2-byte one at offset 2, a 3-byte one at
  offset 1); under `-mos9call` it pads them upward instead. From 5 bytes up, GCC already matches.
  GCC's padding hook doesn't know the call's convention, so the upward padding applies to all
  calls under `-mos9call`, and passing an aggregate smaller than 4 bytes by value to a function
  of the other convention (a `stackcall` function under the flag, an `os9call` one without it) is
  an error. A 1-byte struct is pushed by m68k's `pushqi1` pattern, which normally stores the byte
  at offset 1; under the flag it stores it at offset 0.

**Widened prototypes.** This applies only at the boundary with Microware-compiled code. Between
GCC-compiled functions, prototyped `char`, `short` and `float` parameters, and `float` return
values, work normally under `-mos9call`: both sides pass a `float` as 32 bits, in d0, d1 or a
4-byte stack slot, and return it in d0.

Microware C 3.2 functions are all defined K&R-style, so they receive their arguments in promoted
form: `char` and `short` as `int`, `float` as `double`. By the C standard, a prototype is only
compatible with such a definition if it uses those promoted types. Prototypes *for Microware C 3.2
functions* should therefore use `int` (or `unsigned`) and `double`, never `char`, `short` or
`float`: `extern "C" int f(double x, int c);` rather than `(float x, char c)`. GCC can't tell which
declarations refer to Microware functions, so it doesn't warn about this; getting such
prototypes right is up to whoever writes them.

- **`float` parameters break** when calling a Microware C 3.2 function: GCC passes a prototyped
  `float` as 32 bits, while the callee expects a double.
- **`char`/`short` parameters happen to work:** m68k GCC widens them to a full 32-bit
  slot or register at call sites (`TARGET_PROMOTE_PROTOTYPES`), as Microware callers do, but
  `int` is the correct, portable form.
- **Return types:** functions *written* to be called from, or to call into, Microware-compiled code
  should return `double` rather than `float`. Microware C 3.2, Ultra C 2.5 and GCC `-mos9call` all
  return a double the same way (in d0:d1), while they disagree on `float` (see "Return values").
  Declarations of *existing* functions must still match their definitions: a prototype can't change
  how a function returns.

**`long long`** follows the double rule (d0:d1 as argument 1, otherwise the stack; returned in
d0:d1). This is GCC-only, since Microware C 3.2 has no `long long`.

### Variadic functions

**Background.** Microware C 3.2 has no prototypes and no `stdarg.h` or `varargs.h`. Its callers
can't know that a function is variadic, so `printf(fmt, x)` is compiled like any other call (`fmt`
in d0, `x` in d1). Microware C 3.2's variadic library functions must therefore expect that. How they
read their arguments is undocumented. The usual K&R trick of walking from the address of the last
named parameter can't work: Microware C 3.2's prologue stores d0/d1 below the frame pointer,
separated from the stack arguments by the saved a5 and the return address. Code from that era
supplied its own varargs support.

Ultra C 2.5, which has prototypes, documents a different rule (*Ultra C/C++ Processor Guide*, 68K,
"Passing Arguments to Functions"): named arguments follow the d0/d1 rules, and all variable
arguments go on the stack. Its `stdarg.h` relies on that: `va_list` is a plain pointer, `va_start`
uses a compiler intrinsic to point at the first unnamed argument, and `va_arg` steps through the
stack in 4-byte units.

**Rule for `-mos9call`: variadic calls are passed like unprototyped K&R calls.** The positional
rules apply to *all* arguments, named or not, and the default argument promotions (`float` →
`double`, `char`/`short` → `int`) apply to the unnamed ones as usual. So:

- `g(int a, ...)` called as `g(1, x)`: `a` in d0, then `x` in d1 if it's an int or pointer (a
  double `x` goes on the stack)
- `h(int a, int b, ...)` called as `h(1, 2, x)`: d0, d1, then `x` on the stack
- `f(...)` with no named parameter: the first arguments follow the same rules as any call. Only
  C++ accepts this declaration in GCC 11; C allows it from C23, which GCC supports from GCC 13.
  Before C++26 and C23, the callee can't use `va_start` without a named parameter, so in practice
  it's a declaration for functions implemented elsewhere, which is exactly the Microware case.
  In C, the unprototyped `f()` gives the same calls.

Dual ANSI/K&R headers from that era show why this matters in practice. They wrap declarations in
a prototype macro that expands to the full parameter list for an ANSI compiler and to `()` for
Microware C 3.2. So GCC sees real variadic prototypes (`printf`-style functions, file creation
with optional arguments, and so on), while the implementations behind them were compiled K&R-style
and expect positional arguments. Passing variadic calls like K&R calls is exactly what makes GCC
calls to those functions work.

**Callee side.** A variadic function *defined* with `-mos9call` must find its first arguments in
d0/d1. Only one case needs more than a stack pointer: a function with exactly one named argument,
passed in d0 alone. Its first unnamed argument is in d1 if it's an int or pointer, and on the
stack otherwise; every other unnamed argument is on the stack. So under `-mos9call`, `va_list` is
an array of one structure (as on x86-64) with two pointers: `__stk`, the next stack argument, and
`__d1`, a copy of d1 saved by the prologue (`TARGET_SETUP_INCOMING_VARARGS`), or null once d1 has
been used or skipped, or if it can't hold an argument. `va_arg` (`TARGET_GIMPLIFY_VA_ARG_EXPR`)
takes an int-sized scalar from `*__d1` if it's set, and anything else from the stack, clearing
`__d1` either way. A second `va_start` and `va_copy` work, since `va_arg` never changes the saved
copy. Without `-mos9call`, `va_list` stays a plain pointer, and an `os9call` variadic function is
an error only in that one case.

Level 2 tests (§11) call GCC variadic functions the way Microware C 3.2 code does (ints and
doubles in each position, two named arguments, a double first argument) and from GCC code, at
every optimization level and with `-m68881`.

**Supporting evidence from an earlier port.** The GCC 1.37.1 OS-9 port by T. Shinohara and
A. Seyama (§3) ships a `varargs.h` "for GCC and MicroWare C". Its `va_dcl` declares the first
parameter as a `double`, followed by an `int`: by the Microware rules, a `double` first argument
arrives in d0:d1, so the callee has d0 and d1 next to each other in memory, and `va_arg` walks
through those 8 bytes before moving on to the stack arguments. That is consistent with the
positional rule above for integral arguments: a K&R caller passes `printf(fmt, x)` as `fmt` in d0
and `x` in d1.

**Confirmed by running the library:** with the CD-i `clib.l` converted by `rof2elf` (§6) and linked
with `-mos9call` code, Microware C 3.2's `sprintf` and `sscanf` read their arguments correctly
when called with this positional placement: `sprintf(buf, "%d %s %x %c", -7, "str", 255, 'z')`
gives `-7 str ff z` (Level 3, §11), and a double as an unnamed argument is read from the stack,
high half first: `sprintf(buf, "%d %x %x %d", 7, 1.5, 9)` gives `7 3ff80000 0 9`.

### Return values

- **Scalars:** on `elfos9`, `m68kemb.h` (included after `m68kelf.h`) makes `FUNCTION_VALUE` use
  `LIBCALL_VALUE`, so pointers return in d0 and 64-bit values in d0:d1. (Returning pointers in a0
  only applies to the Linux and NetBSD targets.) Narrow values may stay unwidened, because
  Microware callers widen them themselves.
- **float** is returned as a float in d0, as Microware C 3.2 does. Ultra C 2.5 returns and expects
  a double in d0:d1 instead (§3, tests 28–29), but Microware C 3.2 is the reference. It's also
  the faster choice: the Ultra C 2.5 way costs a float-to-double conversion in the callee, and
  often one back in the caller, which on the CD-i's FPU-less 68070 are software routine calls
  (and trapped, emulated instructions with `-m68881`). As with structs, the Microware C 3.2
  headers declare no `float`-returning functions (the math functions return `double`), so this
  difference doesn't affect library interoperability.
- **With `-m68881`**, GCC normally returns float and double in fp0. Under `-mos9call` they stay in
  d0 (float) and d0:d1 (double), as Ultra C 2.5 does even when it uses the FPU.
- **`long double`, `_Complex` and vector types** are returned in memory, like structs (buffer
  address in a0). Vectors are passed on the stack too.
- **Structs:** the Ultra C 2.5 a0 convention. All aggregates are returned in memory, with the
  buffer address in a0; the callee preserves a0. The two Microware compilers are incompatible here
  (§3), and of the two:
  - **Microware C 3.2's static buffer (PCC convention)** returns the address of a static copy in
    d0. It isn't reentrant, and GCC supports it only through the compile-time macro
    `PCC_STATIC_STRUCT_RETURN` (`calls.c`, `function.c`; used by `m68k/openbsd.h`), which can't
    be switched per option without core changes.
  - **Ultra C 2.5's buffer address in a0** is reentrant and close to what GCC already does:
    `m68kelf.h` sets the struct-value register to a0, but `m68kemb.h` sets
    `DEFAULT_PCC_STRUCT_RETURN 0`, so GCC returns small structs that have an integer mode (1, 2,
    4 or 8 bytes, suitably aligned) in d0/d1. Under `-mos9call`, the return-in-memory hook
    returns true for all aggregates.

  For library interoperability the choice doesn't matter: the Microware C 3.2 headers declare no
  function that returns a struct or union by value, either directly or through a typedef, and
  `div()`/`ldiv()` aren't provided at all. The choice only affects user code compiled by the two
  compilers calling each other, and third-party Microware C 3.2 objects that return structs.

### Register preservation

Microware C 3.2 callers rely on d1 surviving calls, and callees preserve a0, a1 and d2–d7 (per the
manual and the observed output), while d0 is never preserved. So:

- An **os9call function (callee)** saves a0/a1 when it uses them or makes calls (register renaming
  and peephole2, which run after the prologue, are kept off registers it didn't save). That
  includes a0 when it carried the struct-return buffer address, as in Ultra C 2.5. It also saves
  d1 when it uses d1 or makes calls, unless d1 carries an incoming argument or the return value;
  the incoming argument state tells which. d0 needn't be saved (Microware C 3.2 never restores
  it; Ultra C 2.5 does, which is harmless). This reuses the `interrupt_handler` logic in
  `m68k_save_reg`.
- **FPU registers** (with `-m68881`): an os9call callee saves every FPU register it uses,
  including fp0/fp1, which GCC normally treats as scratch. Ultra C 2.5 does the same.
- **GCC callers** keep values in a0/a1 across calls to *prototyped* os9call functions
  (implemented with GCC's per-function ABIs: `TARGET_FNTYPE_ABI` gives prototyped os9call types an
  ABI whose clobbered set lacks a0/a1, and `TARGET_INSN_CALLEE_ABI` finds a call's type from its
  MEM, which refers to the declaration or, for an indirect call, the pointed-to function). d1 and
  fp0/fp1 still count as clobbered. Calls to stack convention functions (`stackcall`, libcalls)
  and to unprototyped functions keep the default ABI: GCC's own declarations of libcall functions
  have the type `int ()`, which `-mos9call` would otherwise make os9call. With `-fipa-ra` (on at
  `-O2`), GCC finds a direct call's ABI from the called declaration through `TARGET_FNTYPE_ABI`,
  without asking `TARGET_INSN_CALLEE_ABI`, so any exclusion is in `m68k_fntype_abi`.
  Microware's libraries satisfy this: every global entry point of Microware C 3.2's `clib.l`,
  `cdi.l` and `math.l` that GCC code can call preserves a0/a1 (assembly routines with `movem` or
  `exg`; the exceptions are `setjmp`/`longjmp`, across which GCC keeps nothing in registers, and
  internal helpers); `cdisys.l` has only equates.
- **Hand-written assembly** called with the OS-9 convention through a prototype must preserve
  a0, a1 and d2–d7, and d1 unless it carries an argument or the result, as Microware's own
  routines do. newlib's os9call `setjmp` preserves a0 as well.
- **Tail calls (sibling calls)** from os9call functions are disabled. Otherwise a non-os9call
  callee could clobber a0/a1 (or d1) after the epilogue has restored them.

**A value passed between calls in a register.** GCC decides the order in which it evaluates a
call's arguments and which registers it uses in between, so a routine that leaves a value in a
register for a later call to pick up (a pointer in a1 for the system call the next library
function makes, say) works only with Microware's compilers, which happen to leave that register
alone. The workaround is a file-scope register variable in the source files that use such a
routine, for example in the routine's header:

### Options and special cases

| Case | Behaviour under `-mos9call` | Why |
|---|---|---|
| `-mshort` (16-bit `int`) | rejected with an error | Microware C 3.2's `int` is 32 bits; argument slots and widening rules assume it |
| `-m68881` | supported, with a warning | OS-9 traps FPU instructions and emulates them, so the code runs on a CD-i's 68070, but slowly. Return values stay in d0/d0:d1 and callees save the FPU registers they use (above) |
| no `-ma6rel` | warning | Microware code expects a6 to point at the static storage area, and `-ma6rel` keeps a6 reserved for that |
| nested functions (GCC extension) | allowed; error when a trampoline would be needed | Taking a nested function's address makes GCC build a trampoline that loads the static chain into a1 before the function can save it. A Microware caller of such a pointer (e.g. a `qsort` comparator) would lose a1. Direct calls are fine |
| `-mrtd` (callee pops the arguments) | rejected with an error | the OS-9 convention has the caller pop the arguments |
| frames of 32 KB or more | a1 is always saved in such functions | GCC's m68k epilogue then uses a1 as an index register while restoring registers. With `movem` that's safe once a1 is in the save mask (the address is computed before loading); the hazard is only in the register-by-register restore path, used when fewer registers are saved |
| `-fstack-limit-symbol` | rejected with an error (with `-m68020` and up) | GCC already disables `-fstack-limit-*` on the 68000/68070 (its check uses `TRAPcc`, a 68020 instruction). On the 68020, the check loads the limit into d0 when it isn't a simple constant (in practice always, under `-mpcrel`), clobbering argument 1. See also "Stack checking" below |
| `-fstack-limit-register` with d0 or d1 | rejected with an error (with `-m68020` and up) | the limit register would collide with the argument registers |
| `-fuse-cxa-atexit` (C++) | rejected with an error | the destructor passed to `__cxa_atexit` is a member function (`METHOD_TYPE`, stack convention), but it's called through a `void (*)(void *)` pointer, which is os9call, so `this` would arrive in d0. `thread_local` destructors always go this way, so they're unsupported |
| `-mos9stkchk` | requires `-ma6rel` (error without it); skipped in `interrupt_handler` functions | `_stkcheck` and its limit live in Microware's a6 static area; interrupt handlers don't run on the process stack. See "Stack checking" |
| `-malign-int`, `-fshort-enums`, `-fpack-struct` | warning | they change the data layout, which otherwise matches Microware C 3.2 exactly (§3) |
| `-pg`, `-finstrument-functions` | rejected | the profiler call sequence clobbers a0, and `mcount` and the instrumentation hooks would have to preserve the incoming d0/d1 |
| `-fprofile-arcs`, `-fprofile-generate` | rejected | they call libgcov (`__gcov_init`, the `__gcov_*_profiler` routines) through declarations with plain function types, so under the flag those calls would be os9call, but libgcov is built without it |
| `__builtin_apply`, `__builtin_apply_args`, `__builtin_return` | unsupported (error, once per file) | they forward arguments by saving all possible argument and return registers; untested with d0/d1 arguments, and rarely used. The error comes from the raw-mode hooks (`TARGET_GET_RAW_ARG_MODE`/`TARGET_GET_RAW_RESULT_MODE`), which only these built-ins use |
| other m68k targets | `-mos9call` is an error, the attributes are ignored with a warning | return values and struct return are only handled for `elfos9` (`M68K_OS9_TARGET` in `m68k-os9.h`) |

**Callbacks and entry points.** Code called from outside GCC-compiled code must use the matching
convention, which `-mos9call` provides:
- `main` is called by the startup code. Microware's standard `cstart.r` passes `argc` and `argv`
  in d0/d1, which matches an os9call `main`. A custom startup routine must do the same, or call
  `main` with the convention `main` was compiled for.
- Callbacks passed to Microware or newlib code (`qsort` comparators, `atexit` functions) and
  handlers called by the runtime or OS-9 (signal and intercept handlers) are ordinary functions,
  so they use the OS-9 convention, as their callers must expect.

The tests cover each of these (§11).

### Stack checking

Microware C 3.2 checks the stack in every function by default (`cc -s` turns it off; the probes in
[`test/os9c/stkchk.c`](test/os9c/stkchk.c) show both compilers' code, compiled like `testos9c.c`
in §3 but without `-s`: `xcc -a -bp stkchk.c` for Microware C 3.2 and
`xcc -mode=compat -to=osk -tp=68k -a -c -bp stkchk.c` for Ultra C 2.5). The two Microware
compilers use different, incompatible mechanisms:

| | Microware C 3.2 (`stkchk-cc32.a`) | Ultra C 2.5 (`stkchk-ucc25.a`) |
|---|---|---|
| check | `move.l #-N,d0` then `bsr _stkcheck` | `sub.l #N,_stklimit(a6)`, and `bsr _stkhandler` on a borrow; `add.l #N,_stklimit(a6)` again on exit |
| placement | after `link` and the register saves, before the locals are allocated | after the prologue |
| `N` | local-variable size plus a margin: 64 bytes in a leaf function, 68 in one that makes calls; saved registers don't count, and calls to runtime helpers (`_T$DAdd`) don't make a function non-leaf | roughly the function's stack use |
| registers | overwrites d0 (the `-N` argument); the function then reloads its arguments from their home slots (§3). It never relies on d1 surviving the call either (probe functions `leaf2`, `bigframe2`, `leafd`) | keeps d1 in its register across the check (`_stkhandler` is only called on overflow) |

GCC's own stack-limit check (`-fstack-limit-*`) uses `TRAPcc`, a 68020 instruction, so GCC
disables it on the 68000/68070. For CD-i programs, whose startup code (`cstart.r`) and libraries
come from Microware C 3.2, the useful mechanism is Microware C 3.2's: **`-mos9stkchk`** (off by
default, unlike Microware C 3.2) emits the same `move.l #-N,d0` / `bsr _stkcheck` sequence on the
68000, so GCC and Microware code share one stack limit and one overflow handler. The option needs
Microware's `cstart.r` and `clib.l`, which provide `_stkcheck` and the limit it checks, so it
depends on `rof2elf` (§6). It requires `-ma6rel` and skips `interrupt_handler` functions (see
"Options and special cases").

GCC doesn't always allocate the locals in `link` (large frames use `link a5,#0` followed by
`add.l`, and without a frame pointer it uses `lea` or `sub`), so it emits the check at the start
of the prologue, before the frame is allocated. Microware C 3.2's margin is what's left *after*
`link` and the register saves, so GCC counts those too:
`N` = frame size + register-save area + 4 (for `link`, if any) + 64, or + 68 if the function
makes calls. GCC treats a function that only calls libgcc helpers (`__mulsi3`, soft-float) as
making calls, where Microware C 3.2 uses 64; that's harmless. When `N` ≤ 128, `moveq #-N,d0` is
enough.

Microware C 3.2 saves registers first and checks afterwards, so whatever `_stkcheck` clobbers has
already been saved. GCC checks first. `_stkcheck`'s contract, from a disassembly of `cstart.r`:
`d0` is `-N` on entry; it adds `sp`, compares the result with `_stbot` (the lowest stack address
so far) and returns if it isn't lower; otherwise it compares with `_mtop` (the limit), stores the
new low point in `_stbot` and returns, or on overflow prints a message and exits. On the normal
path it changes only `d0` and the flags. So GCC saves only `d0` around the check, and only when it
carries an argument (`move.l d0,-(sp)` before, `move.l (sp)+,d0` after).

The sequence is `moveq`/`move.l #-N,d0` and `bsr.w _stkcheck` (`jsr` without `-mpcrel`), an
`unspec_volatile` insn in `m68k.md`. Variables that `_stkcheck` changes must be `volatile` in C
code that reads them, since GCC can't see the change. `_stkcheck` also keeps a low-water mark of
the stack pointer, which `freemem()` and `stacksiz()` report; those are only accurate if all code
is built with stack checking.

### Line ends: `-mos9newline`

On OS-9 a text line ends with a carriage return, and in Microware C the escape `\n` *is* that
carriage return: `'\n'` and `'\r'` are both 13. Microware C 3.2, compiled natively on a CD-i 605,
prints `nl=13 cr=13` for `printf("nl=%d cr=%d\n", '\n', '\r')`; the same source built with GCC
prints `nl=10 cr=13`. Its `"\n"` reaches the terminal as a bare line feed, which OS-9 doesn't take
as the end of a line, and Microware's `fgets` and `readln` read past it.

**`-mos9newline`** makes `\n` a carriage return (13) in GCC too, in character constants, string
literals and `#if` alike, and defines `__OS9NEWLINE__`. A line feed is then `'\l'`, as in
Microware C (C 3.2 gives `'\l'` and `"\l"[0]` as 10), or `'\x0a'`/`'\012'`; without
`-mos9newline`, `\l` stays an unknown escape (a pedantic warning, keeping the `l`). It is a
separate option, **not implied by `-mos9call`**: the calling convention and the meaning of `\n` are
independent, and code using newlib's I/O may want either. Code that passes text to Microware's C
library, or writes OS-9 text files, needs it; code that must build either way can write `'\r'`,
which is 13 in both compilers.

| Kind | `\n` | `\r` | `\l` | `__OS9NEWLINE__` | Used by |
|---|---|---|---|---|---|
| `standard` (as `-mno-os9newline`) | 10 | 13 | unknown escape | undefined | GCC's default |
| `microware` (as `-mos9newline`) | 13 | 13 | 10 | 1 | Microware C 3.2, Ultra C in its other modes: `m68k-os9-xcc`, `m68k-os9-ucc` |
| `swapped` | 13 | 10 | unknown escape | 2 | Ultra C's strict ANSI mode (`-a`), where `\n` and `\r` still differ: `m68k-os9-ucc -a` |

A field in libcpp's `cpp_options` selects the treatment; `convert_escape` (in
`libcpp/charset.c`) gives the escapes their values before the conversion to the execution
character set, so `-fexec-charset` still applies. The m68k `TARGET_CPU_CPP_BUILTINS` sets the
field from the option and defines the macro. Wide character constants (`L'\n'`) follow too; raw
strings have no escapes, so a line break in one stays a line feed.

### Other options for Microware C code

- **`-mbuiltin=stackcall|os9call`** chooses the convention of the runtime functions libgcc also
  calls ("Libraries" below).
- **`-mos9math`**: floating point through OS-9's math module, as Microware C's `-x` ("Floating
  point" below).
- **The `remote` attribute** places data beyond the 64 KB a6 window (§6, "Data beyond 64 KB").
- **Predefined names:** GCC on `m68k-elfos9` predefines what Microware C 3.2's driver does: `_OSK`,
  `_MPF68K` and `_BIG_END` (and `_MPF68020`, `_FPF881` for those CPUs), and as its `cpp` does
  `OSK` and `mc68000` (`OSK` also as `__OSK`/`__OSK__`, and only those in strict ISO C), so
  Microware's `stdio.h`, which tests `OSK`, works unchanged. Ultra C 2.5 in compat mode also
  defines `_UCC` and its revision, and `_FPF881` even for the 68000; `m68k-os9-ucc` defines
  Ultra C's names.

### Floating point: `-mos9math`

Without its `-x`, Microware C calls the floating-point routines of `math.l` (`_T$DCmp` and the
like); with it, it traps to OS-9's math module (`trap #15`), which a CD-i player has in its
system ROM. Microware code compiled either way links with GCC code (`math.l` goes through
`rof2elf`). C 3.2's `xcc -bp` shows what `-x` is: without it, the driver gives `c68` `-t`, which
turns each trap into a call of `math.l`'s `_T$DAdd` and the like, and links `clibn.l` and `math.l`;
with it, `c68` emits the `tcall`s and the driver links `clib.l`. The cross `xcc -a -x` and the
native `cc -a -x` give identical assembly. Ultra C's `-x` is different: it emits 68881
instructions for an F-line emulator.

GCC's own floating point is libgcc's soft-float (`lb1sf68`), in the program, unless
**`-mos9math`**:

- **Inline traps:** without an FPU, GCC emits the traps itself, as C 3.2 does with `-x`. The
  backend's float expanders (`add`, `sub`, `mul`, `div`, the conversions between float, double,
  long and unsigned long, and `cbranch`) load the operands into fixed registers and emit
  `trap #15` and the function code (`T$DAdd` = 14 …): doubles in d0:d1 and d2:d3, floats in d0
  and d1, the result in d0:d1 or d0, a comparison's in the condition codes. C 3.2 does float
  arithmetic in double. With an FPU (`-m68881`) the FPU is used and `-mos9math` changes nothing.
- **Clobbers:** d1 and d2:d3 count as destroyed by every double operation and conversion. The
  *OS-9 Technical Manual* (chapter 6) promises unchanged registers only for `T$DCmp` (d0–d3) and
  `T$FCmp` (d0/d1), and on the CD-i 605 `tan`, `acos` and `T$DAdd` do change d2/d3. Microware C
  3.2 assumes no more: with `-x`, before and after `o68`, it reloads d2:d3 before every double
  operation and keeps register variables in d4–d7 only.
- **Compares** are the math module's (`T$DCmp`, `T$FCmp`) whether or not NaNs are honoured, as in
  Microware C: the module knows no NaNs, and its errors end the program rather than make one, so
  NaNs only come from outside (bit patterns, `nan()`); only `isnan` and `isunordered` (ORDERED and
  UNORDERED) call libgcc's `__unord<mode>2`.
- **Errors** (division by zero, overflow, 0/0, out-of-range conversions, domain errors) raise
  TRAPV and end the program (`000:107`), as in Microware C. `pow(0, -1)` returns 0.
- **`libos9math`** (newlib's `libgloss/m68k`) is linked before libgcc. Its versions of the
  soft-float entry points (`__adddf3` … `__divsf3`, the comparisons, `__unord*`, and the
  conversions between float, double, long and unsigned long) call the math trap, for code that
  still calls them (code compiled without `-mos9math`, and libgcc's own internal calls); its
  comparisons check for NaNs. A constructor links the handler (`F$TLink`), as `cstart.r` does on
  the first trap. libgcc's exception flags (`_fpCCR`) aren't kept, and the 64-bit conversions stay
  in libgcc.
- **`math.h`:** GCC defines `__OS9MATH__`, and newlib's `math.h` includes `<machine/os9math.h>`,
  whose `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `log`, `log10`, `sqrt`, `exp` and `pow` are
  inline traps (`gnu_inline`, so libm's stay for their addresses), with the precision 1E-14 in
  d2:d3 (`pow`: d4:d5), as C 3.2's own `clib.l` passes it; the precision registers are declared
  read-write. A test program of these functions shrinks from 60 KB to 38 KB.

### Libraries

Application code built with `-mos9call` needs every library it calls through ordinary function
calls built with the same convention: newlib (`printf`, …) and, for C++, libstdc++/libsupc++.
These cases need care:

- **libgcc is built *without* `-mos9call`.** The compiler calls its helpers (`__mulsi3`,
  soft-float routines, …) as libcalls, which keep the stack convention, but their *definitions*
  are ordinary functions and would switch convention if compiled with the flag. libgcc's target
  makefile fragment (`libgcc/config/m68k/t-elfos9`) adds `-mno-os9call` in every multilib.
- **Which functions keep the stack convention.** The rule: a function is `stackcall` if its
  definition, or one of its callers, is outside `-mos9call` code (libgcc, assembly). Checked with
  `nm -u` on the `elfos9` `libgcc.a`, that gives:
  - `memcpy` and `memset`: newlib defines them in m68k assembly (`memcpy.S`, `memset.S`), and
    libgcc calls them
  - `strlen`, `malloc` and `free`: newlib defines them in C, but libgcc calls them (the DWARF
    unwinder and emulated TLS)
  - entry points defined in libgcc or libatomic (`_Unwind_Resume`, `__atomic_*`, …), including the
    complex multiply and divide helpers (`__mulsc3` … `__divxc3`), which GCC also calls through
    built-in declarations
  - `abort` (also called by libgcc) takes no arguments and never returns, so either convention
    works; it's listed for type consistency

  `memmove` and `memcmp` aren't called by libgcc and newlib defines them in C, so they stay
  unattributed (os9call under the flag). There is no `atexit` registration from startup code: the
  `elfos9` install has no `crtbegin`/`crtend`.
- **Microware's `clib` instead of newlib: `-mbuiltin=os9call`.** The list above is right for newlib.
  Microware's `clib.l` defines `memcpy`, `memset`, `strlen`, `malloc`, `free` and `abort` with the
  OS-9 convention, so a program linked against it needs them as os9call, including GCC's own
  `memcpy` calls for block moves. `-mbuiltin=os9call` selects that; `-mbuiltin=stackcall` is the
  default. libgcc's own entry points keep the stack convention either way; its DWARF unwinder and
  emulated TLS, which call these functions, can't be used with `-mbuiltin=os9call`.
- **One mechanism for all declarations.** GCC calls some of these functions through its own
  built-in declarations, which have a real function type, so marking their *definitions*
  `stackcall` wouldn't help. Instead, GCC passes every declaration through
  `TARGET_INSERT_ATTRIBUTES` when it's created, including its own built-in declarations (both
  `__builtin_memcpy` and the plain `memcpy`, and `_Unwind_Resume`, which is created late, in
  `build_common_builtin_nodes`). Under `-mos9call` the backend adds `stackcall` there to every
  declaration of the functions above that has no convention attribute: built-ins (recognized by
  their library name), header declarations, definitions, and old code's own redeclarations such
  as K&R `char *malloc();` (which GCC would otherwise only warn about, and then call with the
  wrong convention). So headers, built-ins, definitions and function pointers (`&memcpy`) all
  agree, and GCC keeps treating the functions as built-ins. newlib's headers and C definitions
  need no changes, and its m68k assembly versions stay as they are.
- **libsupc++** (C++, once enabled) calls `_Unwind_*` through the declarations in `unwind.h`,
  which aren't built-ins. Calls also go the other way: the unwinder calls the personality routine
  (`__gxx_personality_v0`) and the exception cleanup function through function pointers. The
  same mechanism covers these: typedefs whose names start with `_Unwind_` (such as
  `_Unwind_Personality_Fn`) get `stackcall` on their function type, and so do declarations of
  `_Unwind_*` functions and of the personality routines.

**Multilibs.** The `m68k-elfos9` GCC has two multilibs, the default and `-mos9call` (directory
`os9call`; `m68k/t-elfos9`, replacing the per-CPU `t-mlibs`), and GCC and newlib are configured
with `--enable-multilib`; the two `libgcc.a` are the same. newlib's `setjmp.S` has an os9call
variant (arguments in d0/d1 when `__OS9CALL__` is defined); with `setjmp`/`longjmp` os9call in
both libraries, `-mbuiltin=os9call` programs (Microware's `clib`) agree too. Variadic functions
can be defined under `-mos9call`, so newlib's `printf` family is built with the flag. There is no
FPU multilib: `-m68020 -m68881` programs link the 68000 newlib (soft-float, and the non-68881
`setjmp`).

**newlib's OS-9 runtime**, in `libgloss/m68k`, built for `m68k-elfos9` in both multilibs:
- `os9-crt0.o`: argc/argv from the parameter string, with the module's name as `argv[0]`;
  constructors; `exit(main(...))`
- `libos9.a`: newlib's system calls through OS-9's: `I$Read`/`I$ReadLn`, `I$Write`/`I$WritLn`,
  `I$Open`/`I$Create`, `I$Close`, `I$Seek`, `I$GetStt`/`I$SetStt`, `I$Delete`, `F$Exit`, `F$ID`,
  `F$Send`, `F$Time`. On terminals (SCF paths) a line feed is written as a carriage return, with
  `I$WritLn`, and read back as a line feed; files are unchanged
- `os9.ld` and `os9.specs`, which adds `-mpcrel -ma6rel`, the startup,
  `-q --no-check-sections -Tos9.ld` and `-los9`. Opt-in (`-specs=os9.specs`) rather than driver
  defaults, so code built without it stays as before (Level 0)
- the heap lies between the data and the stack: newlib's `malloc` needs it contiguous and growing
  upwards, and `F$SRqMem` hands out blocks from the top of memory down. The module reserves
  `__os9_heap` bytes (16 KB) and the shell's `#size` modifier adds more (`prog #64k`)
- the module header comes from `__os9_*` symbols that `os9.ld` provides with defaults (8 KB of
  stack, edition 1), which a program or `--defsym` overrides; `--defsym __jmptbl_size=N`
  reserves `elf2mod`'s jump table

**`m68k-os9-gcc`** (in m68k-os9-tools, with `m68k-os9-` links to the binutils) compiles and links
with `-specs=os9.specs`, then runs `elf2mod`; a program too large for 16-bit calls is linked
again with the jump table size `elf2mod` asks for; `-Wm,` passes options to `elf2mod`. GCC's
driver can't run a tool after linking, hence the wrapper.

**Two fixes to `-ma6rel`**, found by building newlib this way, are on branches of their own for
Murachue's fork (§10, "Repositories and branches"):
- read-only variables that hold addresses (`const char *const tbl[]`, newlib's locale tables)
  were addressed PC-relative, though they need relocating and GCC places them in a writable
  section; now they're data, addressed relative to a6, decided by the type, which every
  translation unit sees: read-only variables whose type contains pointers, structures or unions
  (also incomplete ones: an opaque `struct ops` may hold function pointers) or that are volatile.
  The cost: read-only structure tables use the 64 KB a6 window instead of the code area. A
  read-only variable placed in data for a reason its type doesn't show (an address in an integer,
  a common symbol) is a6-relative in its own translation unit, and GCC warns, since others can't
  know
- libgcc's soft-float routines reached `_fpCCR` through the GOT; now relative to a6, with
  `-ma6rel` defining `__A6REL__`

### Headers for Microware libraries

The `os9call` attribute also works without `-mos9call`, so a header can mark the Microware
library functions it declares, and programs that otherwise keep GCC's stack convention can still
call them. A prototype macro, `_OS9PROTO`, keeps such a header usable by Microware C 3.2 too:

```c
#ifdef __GNUC__
#if defined(__has_attribute)
#if __has_attribute(os9call)
#define _OS9PROTO(p) p __attribute__((os9call))    /* GCC with OS-9 call support */
#endif
#endif
#ifndef _OS9PROTO
#define _OS9PROTO(p) p __os9call_attribute_not_supported_by_this_GCC
#endif
#else
#ifdef __STDC__
#define _OS9PROTO(p) p                             /* other ANSI compilers: see below */
#else
#define _OS9PROTO(p) ()                            /* Microware C 3.2 (K&R) */
#endif
#endif

int create _OS9PROTO((char *name, int mode, int perm, ...));
int _errmsg _OS9PROTO((int nerr, char *msg, ...));
```

- **GCC with OS-9 call support:** each declared function gets the `os9call` attribute, whether or
  not `-mos9call` is in effect. With the flag the attribute is redundant, but harmless.
- **Microware C 3.2** gets K&R declarations (`()`). The macro uses only `#ifdef`, `#ifndef`,
  `#else` and `#endif` outside the GCC branch, since that compiler predates `__has_attribute` and
  may lack `#elif`. Checked with the probe
  [`test/os9c/os9proto.c`](test/os9c/os9proto.c) (output `os9proto-cc32.a`): its preprocessor
  skips the GCC branch, including `#if defined(__has_attribute)` and `#if __has_attribute(…)`,
  but rejects an `#error` there ("illegal '#'"), even though the line is skipped. So the GCC
  branch has no `#error`, and the calls come out as K&R calls, as from GCC.
- **Other ANSI compilers** get plain prototypes. For Ultra C 2.5 in ANSI mode that is wrong for
  variadic functions, since it puts unnamed arguments on the stack.
- **A GCC without `os9call` support** stops with an error rather than silently using the stack
  convention: a deliberate syntax error at each declaration, "expected declaration specifiers
  before '__os9call_attribute_not_supported_by_this_GCC'".
- **Detection:** `__has_attribute(os9call)` (available since GCC 5) checks whether the attribute
  is supported, independently of the flag. `__OS9CALL__` tells whether `-mos9call` itself is on.
- **Variadic functions** such as `create` and `_errmsg` are called with the same positional,
  K&R-style placement as under the flag (see "Variadic functions").
- **Name clashes:** don't declare functions this way that newlib also declares (`printf` and the
  rest of the standard library): that conflicts with newlib's own declarations, and both
  libraries would define them. The pattern is for OS-9- and CD-i-specific functions.
- **Widened prototypes** still apply: the parameter lists inside `_OS9PROTO` must use `int` and
  `double`, never `char`, `short` or `float` (see "Arguments").

`_OS9PROTO` is this project's own pattern for headers that declare Microware library functions.
Dual ANSI/K&R headers from the era used similar prototype macros, without the attribute.

### Implementation points (`gcc/config/m68k/`)

Where the convention lives in the GCC 11 tree (`gcc/config/m68k/`, unless noted):

| Where | GCC's purpose | What it does under the OS-9 convention |
|---|---|---|
| `m68k.h`:<br>`CUMULATIVE_ARGS`<br>`INIT_CUMULATIVE_ARGS` | per-call argument-scanning state | whether the call uses the OS-9 convention (one predicate, given the function type and its attribute; libcalls, `METHOD_TYPE` and `interrupt_handler` functions keep the stack convention), the argument position, and where arg 1 went |
| `m68k.h`:<br>`FUNCTION_ARG_REGNO_P` | which registers can carry arguments | d0 and d1, under `-mos9call` or once an `os9call` attribute has been applied in the translation unit, so code using neither is unchanged (Level 0) |
| `m68k_function_arg`<br>`m68k_function_arg_advance` | where an argument goes | the positional rules, named and unnamed arguments alike |
| `TARGET_FUNCTION_ARG_PADDING` | padding of arguments smaller than their slot | aggregates upward; `pushqi1` in `m68k.md` follows it |
| `TARGET_RETURN_IN_MEMORY`<br>`TARGET_FUNCTION_VALUE` | return values | all aggregates, `long double` and `_Complex` in memory (a0); other values in d0 / d0:d1, also with `-m68881`. A hook rather than the `FUNCTION_VALUE` macro, which only gets the declaration and would miss indirect calls |
| `m68k_save_reg`<br>`m68k_epilogue_uses` | the prologue's saves, live registers at exit | a0/a1 when used or non-leaf; d1 unless it carries an incoming argument or the return value; every call-clobbered register but d0 live at exit, so the epilogue's restores aren't deleted as dead |
| `TARGET_FNTYPE_ABI`<br>`TARGET_INSN_CALLEE_ABI` | per-function ABIs | a0/a1 kept across calls to prototyped os9call functions |
| `m68k_ok_for_sibcall_p` | tail calls | refused from os9call functions, and from stack-convention functions to os9call ones |
| `m68k_attribute_table`<br>`TARGET_COMP_TYPE_ATTRIBUTES` | target attributes, type compatibility | `stackcall`, `os9call` and `remote` as type attributes with `affects_type_identity`; different *effective* conventions are incompatible types; the handlers drop the attribute that matches the flag's default |
| `TARGET_INSERT_ATTRIBUTES` | attributes added to declarations | `stackcall` on the runtime functions of "Libraries" |
| `TARGET_SETUP_INCOMING_VARARGS`<br>`TARGET_BUILD_BUILTIN_VA_LIST`<br>`TARGET_EXPAND_BUILTIN_VA_START`<br>`TARGET_GIMPLIFY_VA_ARG_EXPR` | variadic functions | the `__stk`/`__d1` `va_list` |
| `m68k_trampoline_init`<br>`TARGET_GET_RAW_ARG_MODE`<br>`TARGET_GET_RAW_RESULT_MODE` | trampolines, `__builtin_apply` | errors |
| `m68k_expand_prologue` | the prologue | the `_stkcheck` sequence (`-mos9stkchk`) |
| `m68k_option_override` | option checks | the rules of "Options and special cases" |
| `libcpp/charset.c` | escapes | `-mos9newline` |

Background in the GCC internals manual: "Passing Arguments in Registers", "How Scalar Function
Values Are Returned", "How Large Values Are Returned", "Function Entry and Exit".

## 5. How dependent is the toolchain on ELF?

Very little of it is in the compiler. GCC never writes object files: `cc1` emits assembly text,
and `as` turns it into an ELF `.o`.

| Piece | Tied to ELF? |
|---|---|
| `cc1` (GCC) | Only through the assembly syntax and section names it prints, which come from the target headers (`m68kelf.h`, `elfos.h`, formerly `dbxelf.h`) |
| GNU `as` / `ld` (BFD) | Yes. Modern BFD cannot read or write ROF |
| Linker script (`.data` at -0x8000, `-Wl,-q`) | Yes, an ELF link convention |
| `elf2mod` | Yes, it turns a linked ELF into an OS-9 module |

The ELF-specific things in the target headers are:
- directives: `.section`, `.type`/`.size`, `.weak`, `.hidden`, `.comm`/`.local`, `.ident`
- `.L` local labels and the `%` register prefix
- section names: `.rodata`, `.text.startup`, `-ffunction-sections`, `.init_array` for C++
  constructors
- DWARF debug info

The code generator itself barely cares, and the fork's own changes concern addressing, not the
object format.

The ways to work with Microware object files (ROF):

1. **`rof2elf`** (chosen): convert Microware `.r`/`.l` files to ELF and keep linking with GNU
   `ld` + `elf2mod`. This brings Microware and CD-i libraries into GCC programs.
2. **`elf2rof`** (chosen): convert GCC objects to ROF for Microware's linker `l68`, so GCC code
   can go into Microware-linked programs.
3. **A ROF backend in BFD**, making `as`/`ld`/`objdump` speak ROF natively. Cleanest, but the
   most work.
4. **Make GCC emit Microware `r68` assembly** (`psect`/`vsect`, `dc`/`ds`, no `%`). This ties
   builds to Microware's assembler and linker, and breaks GNU-syntax inline asm. Not chosen for
   the compiler; `gastor68` translates GCC's output to r68 syntax where Microware's assembler
   must take it (§6, "Drop-ins for Microware's tools").

## 6. ROF interoperability: `rof2elf` and `elf2rof`

### The ROF format

From the *OS-9 Assembler/Linker User Manual*, chapter 3 ("Relocatable Program Sections"), section
"Relocatable Object File Format". An ROF has eight sections:
- the header
- external definitions
- object code
- initialized data
- remote initialized data
- debug information
- external references
- local references

- **Header:** sync bytes, type/language, attribute/revision, assembly-valid flag, series,
  date/time, edition, and sizes (static storage, initialized data, code, stack, remote static,
  remote initialized data, debug). It also holds the entry point and uninitialized-trap entry
  offsets, and a NUL-terminated module name.
- **Symbol types:** data/code/equ, initialized/uninitialized, remote/not remote, common.
- **References** (external and local): each one carries type and location flags.
  - Size: 1, 2 or 4 bytes.
  - Relative: PC-relative, relative to the reference's own address.
  - Negative: subtract the symbol's value instead of adding it.
  - Target: code or data, remote or not.
  - There is no addend field; the addend sits in the object bytes (REL style).
- **Libraries** (`.l`) are concatenated ROFs, not `ar` archives.

### Mapping to ELF

| ROF | ELF | Notes |
|---|---|---|
| code | `.text` | one code section per ROF; `.rodata`/`.text.*` get merged into it on the way back |
| initialized / uninitialized data | `.data` / `.bss` | |
| remote data (`vsect remote`) | `.remote.data` / `.remote.bss`, beyond the 64K a6 window | see "Large programs" |
| 2-byte data references (a6-relative) | `R_68K_16` | must agree with the -0x8000 bias in the linker script |
| 4-byte references | `R_68K_32` | in `.data`: pointers, which `elf2mod` relocates at load time. In code: link-time constants, i.e. a6-relative data offsets (`move.l #_iob,a1` then `adda.l a6,a1` in `cstart.r`) or equates, which come out right with the -0x8000 data bias; `elf2mod` accepts these |
| relative 1/2/4 bytes | `R_68K_PC8`/`PC16`/`PC32` | |
| common symbols | ELF COMMON | |
| addend in the instruction bytes | RELA addend | |
| mainline header (type, attributes, edition, stack, entry) | absolute and code symbols `__os9_typelang`, `__os9_attrev`, `__os9_edition`, `__os9_stack`, `__os9_entry`, `__os9_trapent` | |

- **Long calls:** GNU `ld` doesn't build Microware's `_jmptbl` jump table for calls beyond ±32K;
  `elf2mod` does (see "Large programs").
- **Linker-defined symbols** that Microware's libraries expect from their linker (`end`, `btext`,
  …) come from the linker script or from `elf2mod`.
- **Calling convention:** calls between GCC code and converted Microware code need `-mos9call`
  (§4).
- **Constructors:** C++ static constructors would need their own startup mechanism in the
  ELF→ROF (`elf2rof`) direction, since `l68` has nothing like `.init_array`. ROF has no weak
  symbols.

### Prior art: the old binutils ROF backend

The GCC 2.6.2 OS-9 cross port bundles a Cygnus binutils 2.5.2 (1995) with a BFD target for ROF:
`bfd/roff.c` (about 3,400 lines, "hacked from adobe-aout.c by Walter Hunt") plus `bfd/os9.c`.

What it does:
- Reads and writes ROF objects.
- Presents `.l` files as archives.
- Handles 1/2/4-byte, PC-relative, negative and `equ` references.
- Applies the 0x8000 a6 bias to data references.
- Maps onto `.text`/`.data`/`.bss`/`.debug`.

Its gaps:
- It aborts on remote data and OS-9 common symbols.
- Its relocation types are ROF codes rather than m68k ones. Converting with `objcopy` would rely
  on modern BFD's generic remapping by size and PC-relative flag, which can't represent negative
  references or the a6 bias.

### Standalone tools

Porting `roff.c` into binutils 2.35 or newer would mean rewriting nearly all of its BFD glue
(`DEFUN`/`PROTO` macros, `bfd_read` → `bfd_bread`, section size fields, target jump tables,
archive interfaces, the removed "seclet" linker), and mixed-format ELF links would stay fragile.
So the conversion is done by standalone tools, specified by the Assembler/Linker manual, with
`roff.c` for real-world details, in the m68k-os9-tools repository next to `elf2mod`, which builds
them in the `Dockerfile`'s `elf2mod` step. binutils stays unchanged. A BFD port remains possible
if `nm`/`objdump` on ROF or direct `ld` input turn out to matter.

- **`rof2elf`** (`rof2elf.md`) parses ROF, splits `.l` files, and writes ELF relocatables
  directly (no libbfd), with exactly the relocations above. The front ends convert Microware's
  libraries and objects on the fly into a cache (`m68k-os9-xcc.md`, "Converting them"); by hand,
  vendor libraries are converted once into `.a` archives, one's own objects through a Makefile
  rule (`%.o: %.r`).
- **`elf2rof`** (`elf2rof.md`) reads ELF relocatables and `ar` archives directly and writes ROF
  edition 9, one psect per object; an archive becomes a `.l` library. Read-only sections become
  code, PC-relative references within the code and references to absolute symbols are resolved,
  PLT relocations are PC-relative, and the `__os9_*` symbols give a mainline's header. Comparing
  with `l68` showed what the manual doesn't say:
  - every ROF ends with 16 zero bytes, which `rdump` and `l68` skip; a library without them is
    misread
  - `l68` doesn't compute 4-byte relative references; Microware's assemblers write an external
    reference plus a negated reference to the psect's code instead, and so does `elf2rof`
  - the assemblers sort definitions and external references by name and write local references
    in descending order; `l68` pulls library members in the order of the external references and
    builds the initialized data references in reverse, so `elf2rof` does the same, for identical
    modules
  - `l68 -a` redirects far `bsr.w` and `lea`, but not `bra.w`, which GCC uses for tail calls
    with `-mbsrw`: large programs for `l68` need no `-mbsrw` or `-fno-optimize-sibling-calls`
  - `elf2rof -k` skips archive members it can't convert

### Large programs

On the 68000 (and the CD-i's 68070), both code and data are normally reached with 16-bit
displacements: calls and PC-relative references reach ±32 KB, and a6-relative data reaches the
64 KB around a6 (which points 0x8000 into the data area). Larger programs need two extensions.

#### Code beyond ±32 KB: a jump table, built by `elf2mod`

Microware's linker `l68` solves this with a jump table, `_jmptbl`, in the data area (`l68 -a`,
which `cc` uses by default; *OS-9 Assembler/Linker User Manual*, chapter 6 "The Linker" and
chapter 7 "OS-9 Programming Techniques"). Each entry is a `jmp` to an absolute address (fixed up
when OS-9 loads the module), and each call that's too far is redirected through an entry, with
one entry per unreachable destination. `l68` redirects `bsr.w` and PC-relative `lea`/`pea`;
conditional branches (`Bcc`, `DBcc`) stay limited to ±32K. `roff.c` did the same in its GNU
linker. Here `elf2mod` does it, after linking, which keeps binutils unchanged, and adds `bra.w`
(tail calls):

1. Compile as usual. With `-mbsrw`, calls are `bsr.w`; without it, `-mpcrel` calls are
   `lea f(pc),aN` followed by `jsr (aN)`. Both forms are patchable, so `-mbsrw` isn't required.
2. Link with `-q` (keep relocations, as already required) and `--noinhibit-exec`. ld then still
   reports "relocation truncated to fit" for every call that's too far, but writes the output
   anyway, exits with status 0, and keeps the relocations.
3. `elf2mod` finds the overflowed relocations (`R_68K_PLT16` for most `-mbsrw` calls, `R_68K_PC16`
   for calls to `static` functions in other sections and for PC-relative address loads). It
   identifies each instruction by its opcode word just before the relocation (checked under a
   mask), not by the relocation type, and refuses anything it doesn't recognise. It gives each far
   target one table entry (`jmp f`, `$4EF9` plus a 32-bit address, with a load-time relocation
   like `R_68K_32` in `.data`), and patches the instruction. Each patch keeps the instruction's
   size, so nothing else moves:

| Instruction | Becomes |
|---|---|
| `bsr.w f` (call) | `jsr _jmptbl+x(a6)` |
| `bra.w f` (tail call) | `jmp _jmptbl+x(a6)` |
| `lea f(pc),An` (taking the address) | `movea.l _jmptbl+x+2(a6),An`: loads the entry's absolute address, i.e. the real address of `f`, so function-pointer comparisons stay correct |
| `pea f(pc)` (pushing the address) | `move.l _jmptbl+x+2(a6),-(sp)` |

- **Space for the table** must already exist inside a6's window, because the data layout is fixed
  after linking. `l68` puts the table at the end of the initialized data, i.e. at the end of the
  64 KB a6 area and before the remote data (the *OS-9 C Language User Manual*, chapter 2, shows
  this layout for the `remote` storage class). The linker script reserves `_jmptbl` to
  `_ejmptbl` at the end of `.data` too (`--defsym __jmptbl_size=N`); `elf2mod` reports how many
  entries are needed, and `m68k-os9-gcc` and `m68k-os9-l68` link a second time with that size.
- **The table must stay reachable:** `elf2mod` checks that the end of `_jmptbl` is within a6's
  reach (a6 + 0x7FFF); a large `.data` could push it out.
- **Condition codes:** `pea` doesn't change them, but its replacement `move.l` does. That's
  harmless for GCC's code, but matters for hand-written assembly that relies on them.
- **Leftover overflows are errors.** Because ld exits with status 0 under `--noinhibit-exec`,
  `elf2mod` fails if any overflowed relocation remains that it can't patch, e.g. a PC-relative
  *read* of a far constant, or a far address load into a data register.
- **Converted Microware objects** call externals with `bsr.w` and rely on this mechanism, so it
  covers them too.

#### Branches within a function

The jump table only covers calls and address loads. Branches *within* a function are limited to
±32 KB, as with Microware C 3.2 (its linker manual: `Bcc` and `DBcc` "are still limited to the
32K restriction"). GCC emits relaxable branches (`jgt`, `jbra`, …), and gas chooses the size:

| Assembled with | A branch beyond ±32 KB becomes | Usable for OS-9 |
|---|---|---|
| a 68020-class CPU | `bgt.l` (32-bit PC-relative) | no: not a 68000/68070 instruction |
| `-mcpu=68000`, no `--pcrel` | an inverted short branch plus `jmp` to an absolute address (`R_68K_32` in `.text`) | no: OS-9 code must be position-independent |
| `-mcpu=68000 --pcrel` (what `gcc -mpcrel` passes) | an error: "value … out of range" | no, but it fails at compile time |

So with this toolchain's flags, a function containing a branch longer than 32 KB fails to
compile. gas could be taught a position-independent long form, but binutils stays unchanged, so
this is a documented limitation; such functions are very rare. The same applies to
`-freorder-blocks-and-partition`, which moves cold code to `.text.unlikely` and reaches it with
conditional branches: it's disabled by default for this target, and should stay off for large
programs.

**Pitfall, the assembler's default CPU:** run by hand, `m68k-elfos9-as` defaults to a 68020-class
CPU, despite the `--with-cpu=68000` passed to the binutils build. It then silently turns far
relaxable branches into 68020-only `bcc.l` instructions. Through `gcc`, the correct options
(`-mcpu=68000 --pcrel`) are passed, but hand-written assembly assembled directly should use
`m68k-elfos9-as -m68000 --pcrel`.

#### Data beyond 64 KB: remote data

Variables that don't fit in the 64 KB a6 window are marked *remote*, like Microware C 3.2's `remote`
storage class (*OS-9 C Language User Manual*, chapter 2; Microware C 3.2 also has `-k0l`, 32-bit
offsets for all data):

- The `remote` attribute places them in `.remote.data` / `.remote.bss` sections, which the linker
  script puts after the normal data, beyond the window. (Not `.data.remote` / `.bss.remote`:
  linker scripts' `.data.*` and `.bss.*` patterns would capture those.)
- GCC accesses them with a 32-bit offset in an index register, e.g. `move.l #sym,dN` followed by
  `0(a6,dN.l)`; small data keeps the fast 16-bit form. (The GCC 1.37.1 OS-9 port's `-mremote`
  did the same.) The attribute marks the symbol (`TARGET_ENCODE_SECTION_INFO`, which also names
  the section, since GCC puts uninitialized variables in `.bss` without asking
  `TARGET_ASM_SELECT_SECTION`). An address of a remote variable is not a legitimate constant or
  address; the address hooks and the `movsi` expander turn it into a6 plus `move.l #sym`. The
  attribute needs `-ma6rel`, and `TARGET_SECTION_TYPE_FLAGS` makes `.remote.bss` `@nobits`.
- `elf2mod` accepts these 32-bit references from code to data as link-time constants (a6-relative
  offsets), not as pointers needing load-time relocation.
- `rof2elf` maps Microware's remote vsects onto the same sections.
- **The full 64 KB window:** with data from -0x8000, more than 32 KB of data crosses from
  0xFFFFFFFF to 0. GNU `ld` only accepts that with `--no-check-sections`. With the option, the
  window holds up to 64 KB, as with Microware C 3.2, and remote data follows directly.
- **Layout:** the data area then extends past 0, so `.text` goes above it (e.g. at `0x400000`);
  `elf2mod` accepts any `.text` address. The module's initialized data is a single block, so
  `.bss` goes before `.data` (`elf2mod` takes the data area's start from whichever comes first):
  then `.data` and `.remote.data` are adjacent, no zeros are stored for `.bss`, and the jump table
  sits at the end of the initialized data, as with `l68`.

### Debug symbols for Microware's debuggers

Microware's debuggers read two files that Microware's linker writes with `l68 -g` (or `cc -g`).
They're placed in an `STB` directory next to the program if one exists:

- `<program>.stb`, a **symbol module**: global code and data symbols. Used by the user-state
  debugger `debug` and by the source-level debugger SrcDbg.
- `<program>.dbg`, **source-level information**: line numbers, local variables and types. Used by
  SrcDbg. It's only produced when the `.r` files were compiled with `-g`.

SrcDbg can be told to skip either file, so the two can be supported independently.

#### `.stb` symbol module: `elf2mod -g`

The format is specified in Appendix A of the *OS-9/68000 User-State Debugger* manual, with an
example dump. It's an ordinary OS-9 data module:

| Part | Contents |
|---|---|
| module header | standard 48-byte OS-9 module header (type: data module) |
| name | NUL-terminated module name (`<program>.stb`) |
| STB header | 2-byte STB format number (0x0100), 4-byte CRC of the program module, 4-byte offset to the symbol entries, 4-byte number of entries, padding to the next 16-byte offset |
| symbol entries | sorted by ascending value; each is a 4-byte value, a 2-byte type flag (low 3 bits: 0 uninitialised data, 1 initialised data, 2 remote data, 4 program text, 6 absolute; l68 also uses 3 for initialised remote data, as in ROF definitions) and a 4-byte name offset |
| names | NUL-terminated symbol names |
| module CRC | as for any OS-9 module |

The program-module CRC lets the debugger check that the symbols match the program. `elf2mod`
builds the program module and its CRC anyway, so it writes the `.stb` from the linked ELF's symbol
table (`elf2mod -g`, `elf2mod.md`). What the manual doesn't say, from `roff.c` and from comparisons
with Ultra C's `l68 -g` and Microware C 3.2's `l68 -g` (`test/l68cmp`), all reproduced:

- the type flag 0x2000 marks the symbols the linker defines: `btext`, `bname`, `etext` (code,
  0x2004), `end` and `_jmptbl` (data, 0x2001); `elf2mod` adds them with l68's values. `_jmptbl`
  only in modules that may have a jump table (the program header's layout: programs, trap
  handlers, `-i` system modules), not in drivers, descriptors or file managers
- the two linkers differ, so `elf2mod` has two styles: C 3.2's l68 (the default) also flags the
  symbols other psects refer to, and lists equal values in reverse definition order; Ultra C's
  l68 also defines `_btext`, `_bname`, `_etext`, `_bdata`/`bdata` and `_enddata`, lists equal
  values in definition order, and puts the symbol module's header parity at offset 0x28 rather
  than 0x2E (`--stb=ucc`); entries with the same value are ordered by object, as each linker
  defines them
- the module owner comes from the `GRPUSER` environment variable, with both linkers (1.0 if
  unset; the native OS-9 `l68` takes the process's owner); `elf2mod` reads it too (0.0 if unset),
  and has `--owner`

`test/l68cmp/run.sh` links the same ROFs with `l68` and with `rof2elf`, GNU ld (in l68's order)
and `elf2mod`: the symbol modules list the same symbols, and the program modules are identical
except for the order of the data relocation table, and so the CRCs. Microware's tools are only
used locally (`MWOS`, `MWLIB`, or `MWBUILT` for a build made under vDos with `vdos.bat`).
Ultra C's assembler writes ROF edition 9.1, with 32-bit counts, which `rof2elf` reads.

#### `.dbg` source-level information

None of the available manuals describe the contents of `.dbg` files. The Assembler/Linker manual
only calls the ROF "Debug Information" section variable-length, and says `l68 -g` makes a `.dbg`
when the `.r` files contain debug information. `roff.c` writes a `.dbg` with a magic number and
the program CRC (at offset 6), followed by the collected debug sections; by Hunt's announcement,
its debug support was taken from Stephan Paschedag's OS-9 port of GCC 2.5.8.

### Drop-ins for Microware's tools

- **`m68k-os9-r68`**, a drop-in for Microware's `r68`: `r68togas` translates r68 syntax to GNU
  `as` syntax, in the dialect of C 3.2's or Ultra C's assembler (`-dialect=`), and objects come
  out as ELF or, with `-obj=rof`, as ROF.
- **`m68k-os9-l68`** and **`m68k-os9-libgen`**, drop-ins for Microware's linker and librarian,
  linking with GNU ld and `elf2mod`, with Microware's symbol modules, jump tables and library
  member order.

## 7. Microware tools used for testing

> **Copyright notice.** Microware OS-9 and its development tools are proprietary. Microware LP,
> which says it owns all OS-9 copyrights and trademarks, enforces this: in August 2026 a [DMCA
> notice][microware-dmca] it filed got a public GitHub copy of OS-9 development software blocked.
> This project therefore does not link to, copy or redistribute any Microware tools, libraries or
> headers. The only tool outputs committed are the assembler listings in `test/os9c`: what Microware
> C 3.2 and Ultra C 2.5 make of this project's own probe programs, kept as the evidence for §3 and
> §4. The tools below are used only locally, by developers who have them, to observe their
> behaviour. Everything else in this project is built from the public manuals and from that
> observation.

[microware-dmca]: https://github.com/github/dmca/blob/master/2026/08/2026-08-05-microware.md

- **Microware Ultra C 2.5**, Windows-hosted: `xcc`, `r68`, `l68`, `libgen`, `rdump`, `deasm`, with
  its manuals *Using Ultra C/C++*, the *Ultra C/C++ Processor Guide* (with a 68K ABI section on
  register usage, argument passing and struct return) and the *Ultra C Library Reference*. To run
  its `xcc` from a POSIX-style shell (Git Bash, MSYS2) on Windows:

  ```sh
  export MWOS='<path to the installation, Windows syntax>'
  export PATH="<installation>/DOS/BIN:$PATH"
  MSYS2_ARG_CONV_EXCL='*' xcc.exe -mode=compat -to=osk -tp=68k -a -c -s file.c   # → file.a
  ```

  Gotchas:
  - Without its tools' directory on `PATH`, phase launches fail with "argument list length error
    while forking".
  - `-tp=68000` and `-tp=070` are rejected; use `-tp=68k`.
  - Compat mode uses the old `cc` option set (`-a` for assembly, `-bp` to show phases).
  - Set `MWOS` rather than using `-mw=`.
  - Float code comes out with 68881 instructions; ignore it when probing argument placement.
- **Microware C 3.2**, the original compiler, in two forms:
  - **DOS-hosted cross compiler.** The `xcc` driver runs the phases `cpp`, `c68` (compiler), `o68`
    (optimizer), `r68` (assembler) and `l68` (linker); headers and libraries are found through the
    `CDEF`/`CLIB` environment variables. It runs in a DOS emulator such as vDos, DOSBox or MS-DOS
    Player. Same options as native `cc`: `xcc -a -s file.c` → `file.a`.
  - **Native `cc`** inside CD-i Emulator (§9).

  Either one confirms the §3 results with the original compiler.

### Microware's other host tools

| Tool | What it does | Here |
|---|---|---|
| `r68` | the assembler | `m68k-os9-r68` |

## 8. Build and host environments

GCC cannot be built with MSVC (Visual Studio). It needs a POSIX shell environment (configure,
GNU make, sed/awk, m4, flex/bison) and a GCC-compatible host compiler. Git for Windows' Git Bash
is a cut-down MSYS2 runtime with neither a compiler nor a package manager.

Development builds use **WSL2 + Ubuntu**: the same environment as the `Dockerfile`, and the
fastest builds. Windows tools such as `xcc.exe` can be called from inside WSL for compatibility
testing. Keep the build directory inside the Linux filesystem (e.g. `~/build`), not under
`/mnt/c`, which is slow for builds. MSYS2 with mingw-w64 GCC also works (below), roughly 3–5×
slower; Cygwin is slower still.

On a 4-core machine under WSL2: `cc1` + `libgcc` only take ~10–20 minutes, the full toolchain
~30–45 minutes, incremental backend rebuilds a minute or two; the disk use stays under ~15 GB
including the distribution. Setup: WSL2 with Ubuntu, the `apt` dependencies listed in the
`Dockerfile`, then GCC configured as in the `Dockerfile`
(`--target=m68k-elfos9 --with-cpu=68000 --enable-languages=c …`).

### Windows as a host

The toolchain also runs natively on Windows, without WSL or Docker:

- **Canadian cross** on Linux: binutils, GCC and the host tools configured with
  `--host=x86_64-w64-mingw32` (or `i686-w64-mingw32`; the distribution's mingw-w64 cross
  compilers), with the Linux-hosted `m68k-elfos9` compilers built first for the target libraries.
- **Native MSYS2** (MINGW64 and MINGW32), so the Windows binaries don't depend on the Linux build
  alone.
- **The target libraries** (newlib with libgloss's OS-9 runtime and `libos9math`, libgcc, both
  multilibs) are the same files on any host; the Windows packages take them from the Linux build.
- **Per component:** binutils and GCC build with mingw-w64 as they are. `elf2mod` needs BFD, so
  a mingw-w64 `libbfd` from the same binutils build. `rof2elf` and `elf2rof` are plain C. The
  front ends (`m68k-os9-gcc`, `m68k-os9-xcc` and its Ultra C mode `m68k-os9-ucc`,
  `m68k-os9-l68`, `m68k-os9-libgen`, `m68k-os9-r68`) are C on libiberty, which runs programs
  through `pex_one` as GCC's driver does, with what the hosts do differently in one file
  (`hostsys.c`): drive letters, file names regardless of case, replacing a file (`MoveFileEx`),
  the temporary directory. That is why they're C rather than shell scripts.
- **The tests stay POSIX** (Makefiles, shell scripts, Musashi, DejaGnu): on Windows they run
  under WSL or MSYS2. Windows programs (`cdirun.exe`, Ultra C's `l68.exe`) are called from WSL.

## 9. Running tests on OS-9: `cdirun`

**`cdirun`**, a command-line client in the CD-i Emulator version 0.6.x tools, runs commands on the
OS-9 shell of a CD-i player (over a serial port or the network) or of [CD-i Emulator][cdiemu]
(`cdiemu`) by CD-i Fan, where the shell runs on an emulated serial port, and copies files both
ways. `cdiemu` emulates CD-i hardware with OS-9 running on it, and runs Microware tools such as
the native `cc` from a Microware disk image.

[cdiemu]: https://www.cdiemu.org

The Windows version (`wcdiemu`) connects each serial port to its terminal program (`winterm`)
through its terminal protocol. `cdirun` attaches to such a port in the terminal's place: the
emulator pauses the terminal window, mirrors the output to it and gives the port back
afterwards, extensions of the protocol made for `cdirun`.

What the tests use:
- `cdirun COMMAND...` sends a command line and writes its output until the shell prompts again.
- On OS-9, programs are run from memory: `attr NAME -e -pe; load -d NAME; NAME` (the shell
  looks for programs only in memory and the execution directory). Microware's `cstart.r` ignores
  what `main` returns, so a test reports through `exit()`.

`make check-os9` and the other OS-9 targets in `test/abi-exec` (§11) run the Level 3 tests this
way, with `CDIRUN=` naming the command, so a wrapper can reach a player by other means.
`cdiemu` cannot mount a host directory as an OS-9 device, so files travel over the serial line
(about 300 bytes a second in the emulator).

A CD-i player on a network is reached in a similar way: a telnet session to the player, bridged to
a `cdirun` terminal, takes the place of the serial port, and files travel by ftp from the PC
instead of Kermit, much faster than the serial line. `test/abi-exec/cdirun-ftp.sh` is a `CDIRUN=`
wrapper for this.

## 10. Licensing and upstreaming

### Fork patches: authorship and license

Murachue's fork commits (2021) are Murachue's own, authored and committed by Murachue; this table
describes them. This work's commits are on the `-compat` branches (see "Repositories and branches"
below).
The upstream split points, fetched shallowly and tagged locally in each submodule:

| Submodule | Upstream split | Murachue's changes |
|---|---|---|
| gcc | `releases/gcc-11.1.0` = `50bc918` (tag `gcc-11.1.0-base`) | 9 commits, 7 files, +89/−15 |
| binutils-gdb | the commit `2cb5c79` *is* upstream "2.35 Release" | none |
| newlib-cygwin | `415fdd4` newlib 4.1.0 (tag `newlib-4.1.0-base`) | 2 commits, `newlib/configure.host`, +5/−1 |
| psximager | `9c32ba2` of cebix/psximager (tag `cebix-base`) | 2 commits, `src/psxbuild.cpp`, +36/−13 |
| elf2mod | no upstream (Murachue's own; README says MIT) | — |

There is no explicit license statement or `Signed-off-by:` on the patches. The only explicit
license in this repo is MIT for the `Dockerfile`, and that header excludes the built image. But
the GCC patches modify files under GPL version 3 or later, and publishing modified GPL code means
it is distributed under the GPL. So they are effectively GPLv3+, and newlib's patches fall under
newlib's licenses. The same holds for this work's changes to GCC and newlib.

### GCC's AI policy

The [GCC AI policy][gcc-ai-policy], adopted 29 July 2026 and to be reviewed at the start of 2027:

[gcc-ai-policy]: https://gcc.gnu.org/ai-policy.html

- GCC declines legally significant contributions (more than roughly 15 lines) that include or
  are derived from LLM-generated content.
- Small LLM-generated contributions may be accepted if clearly marked.
- **Test cases are an exception:** they may be LLM-generated even when large.
- Commits containing LLM-generated content need an `Assisted-by:` tag.
- Only a human may give the DCO `Signed-off-by:`, and an LLM may not commit.
- Using AI for research, analysis, bug finding, review and debugging is fine, as long as its
  output doesn't end up in the contribution.

"Legally significant" applies cumulatively. The [GNU maintainers' guide][gnu-legally-significant]
notes that a series of small changes by the same person can add up to a significant contribution,
so splitting LLM-written code into sub-15-line patches doesn't change its status.

[gnu-legally-significant]: https://www.gnu.org/prep/maintain/html_node/Legally-Significant.html

Murachue's 2021 patches are human-written and unaffected. Upstreaming them would still need:
- ChangeLog entries and `invoke.texi` documentation
- a proper header for `m68k-os9.h`
- a real fix in place of the "HACK" commit
- removing `dbxelf.h`
- checking that the current GNU `config.sub` still accepts `elfos9` (the pinned copies do)
- a maintainer for the target, and posted testsuite results
- preferably Murachue's own DCO sign-off; they can be contacted via GitHub

### Decision

**This work's compiler changes stay in the fork.** `-mos9call` and the other OS-9 options are
written with AI assistance, so they can't go into GCC mainline under the current policy. The
standalone tools (`rof2elf`, `elf2rof`, the drop-ins) aren't affected by GCC's policy. The four gas
fixes (§2) are meant for upstream binutils.

### Repositories and branches

Development happens in forks under [github.com/cdifan][cdifan]:

[cdifan]: https://github.com/cdifan

- **`cdifan/toolchaincdi`** (forked from `murachue/toolchaincdi`): the superproject, branch
  `main`. CI publishes `ghcr.io/cdifan/toolchaincdi:latest` on every push to `main`.
- **`cdifan/gcc`** (forked from `gcc-mirror/gcc`, so upstream branches and tags are available):
  Murachue's **`11.1.0-os9`** branch is kept unchanged as the reference. This work is on
  **`11.1.0-os9-compat`**, branched from it, which `src/gcc` pins.
- **Fixes to Murachue's own code** are on separate branches from `11.1.0-os9`, one commit each,
  so they can be offered to Murachue's fork, and are merged into `11.1.0-os9-compat`:
  `11.1.0-os9-const-pointers` (read-only variables holding addresses are a6-relative data) and
  `11.1.0-os9-lb1sf68-a6rel` (libgcc's soft-float routines reach `_fpCCR` relative to a6, and
  `-ma6rel` defines `__A6REL__`). Both change code built without `-mos9call`, so Level 0 compares
  with Murachue's branch plus these fixes (§11). They're AI-assisted, like the rest of the fork:
  whether to take them is Murachue's call.
- **`cdifan/binutils-gdb`**: branch `m68k-gas-fixes`, upstream 2.35 with the four gas fixes (§2).
- **`cdifan/newlib-cygwin`** (forked from `murachue/newlib-cygwin`): branch
  `newlib-4.1.0-os9-compat`, with the os9call `setjmp`/`longjmp`, `libos9math` and the OS-9
  runtime (§4, "Libraries").

The upstream branch of each fork is kept as it is; the work branch has a `-compat` suffix.

### Alternative (not chosen): human-written code with AI guidance

If upstream inclusion becomes a goal, a human could write the compiler code while AI assistance
stays within what the policy allows. That would mean:
- design specs: the rules and invariants, as in §3–§4
- naming insertion points, and explaining GCC internals
- reviewing the human's patches and debugging failures, describing problems rather than
  supplying replacement code
- writing the test cases, which the policy allows outright

Detailed pseudocode that gets transcribed line by line should be avoided, because the result
would arguably be "derived from LLM-generated content". When in doubt, ask on the gcc mailing
list first. The insertion points are listed in §4 ("Implementation points").

## 11. Tests

Test cases may be written with AI assistance; GCC's AI policy explicitly allows LLM-generated
test cases (§10). The reference for expected behaviour is the Microware C 3.2 output
([`test/os9c/testos9c-cc32.a`](test/os9c/testos9c-cc32.a)) and the rules derived from it in §3.
The exception is struct return, which follows Ultra C 2.5
([`test/os9c/testos9c-ucc25.a`](test/os9c/testos9c-ucc25.a)), as decided in §4.

### Level 0: no-regression baseline

Without the OS-9 options, the compiler behaves exactly as before.

- `test/baseline/run.sh` compiles a fixed set of sources, the probe `test/os9c/testos9c.c` plus
  realistic code (a selection of newlib and libgcc sources), with the reference compiler and with
  the changed one, at `-O0` and `-O2`, with the usual OS-9 flags (`-mpcrel -ma6rel`, with and
  without `-mbsrw`), and requires **byte-identical** assembly. The reference is Murachue's branch
  plus the fixes that deliberately change it (§10), as built from `11.1.0-os9-const-pointers`
  (`run.sh` explains; with the unmodified compiler, `strftime` differs).
- The baselines aren't committed: they would go stale with every compiler build.

### Level 1: compile-only ABI checks

These verify where values go, by scanning the generated assembly. No m68k hardware or simulator is
needed.

- **Framework:** GCC's own DejaGnu testsuite, as `gcc/testsuite/gcc.target/m68k/os9*.c` (on the
  `11.1.0-os9-compat` branch of `cdifan/gcc`) with `{ dg-do compile }`,
  `{ dg-options "-mos9call ..." }` and `{ dg-final { scan-assembler ... } }`. Run with
  `make check-gcc RUNTESTFLAGS="m68k.exp=os9*"` (requires `dejagnu`), with the compile-only
  board in `test/dejagnu`.
- **Marker constants:** call sites pass distinctive values, e.g.
  `f(0x11111111, 0x22222222, 0x33333333)`, so each pattern pins one fact: `#0x11111111` → `%d0`,
  `#0x22222222` → `%d1`, `#0x33333333` pushed. Callees return or store a specific parameter, so
  the pattern shows where the callee reads it from.

### Level 2: execution-level ABI checks

Level 1 can't prove that registers actually survive a call, or that values arrive intact. Level 2
runs code (`test/abi-exec`).

- **Harness:** a small host program built around the Musashi 68000 CPU emulator library
  (permissively licensed, included as a submodule). It loads a linked test image (ELF, no OS), sets
  up a stack and a6 (for `-ma6rel` code), runs it from its entry point, and reports the exit
  status. It emulates the few OS-9 system calls the tests make (`trap #0`): `F$Exit`, with which
  the startup (`crt0`) exits with `main`'s result, and `I$Write`/`I$WritLn` on the standard
  paths, so the same images also run on OS-9 itself (below). With `-m` it loads an OS-9 module as
  OS-9 does (copying the initialized data and relocating its references; header parity and CRC
  checked), and with `-v` checks a `.stb`. The assembly stubs below fill registers with marker
  values and check them around calls.
- **Microware side:** short hand-written GNU-syntax assembly stubs reproduce the exact call and
  return sequences of Microware C 3.2 (taken from `testos9c-cc32.a`), and for struct return those
  of Ultra C 2.5 (from `testos9c-ucc25.a`). They check:
  - a Microware C 3.2-style caller calling a GCC `-mos9call` function: arguments received correctly,
    and d1 (when not an argument/return register), a0/a1 and d2–d7 preserved
  - a GCC `-mos9call` caller calling a Microware C 3.2-style callee: arguments placed correctly, and
    no reliance on d0 surviving; a0/a1 kept across calls (`tests/keep.c`, with a stack convention
    stub that clobbers a0/a1)
  - doubles in d0:d1, the stack layout, and caller cleanup
  - struct return in the a0 convention
  - GCC variadic functions called Microware C 3.2-style (first arguments in d0/d1), reading every
    argument correctly with `va_arg`, at every optimization level and with `-m68881`
- **GCC↔GCC:** `-mos9call` code calling itself, including through function pointers, mixed with
  non-os9call code (libcalls, member functions).
- **Modules:** `make check-mod` runs every Level 2 test as a module built by `elf2mod`, plus
  `modtests/far.c`, whose `bsr.w`, `bra.w`, `lea` and `pea` references cross 40 KB of code
  through the jump table, and checks every module's header parity and CRC, and its `.stb`, as OS-9
  does. Remote data: 40 KB of normal data plus a 70,000-byte remote array, at every optimization
  level.
- **newlib:** `make check-newlib` runs `nltests/` in both multilibs: `sprintf`, `sscanf`,
  `strtol`, `qsort` calling back, a `va_list` passed to `vsnprintf`, `setjmp`/`longjmp` and
  `malloc`, as OS-9 modules, since newlib's stdio makes programs larger than 32 KB.
- **r68 sources:** `make check-r68` runs Level 2 tests whose assembly side is written in
  Microware's r68 syntax (`r68tests/`, the code of `tests/*.S`), translated by `r68togas` and
  assembled by GNU `as`, as `m68k-os9-r68` does; `make check-gastor68` compiles the tests' C side
  with `-S`, translates it to r68 syntax with `gastor68` and back with `r68togas`, and runs the
  result, at `-O0` and `-O2`.
- **On OS-9 itself:** `make check-os9mod CDIRUN=…` runs the `check-mod` modules (`tests/` and
  `modtests/` at `-O2 -mpcrel -ma6rel -mos9call`) on a CD-i 605 through `cdirun`, like
  `check-os9` (Level 3). It needs none of Microware's files. `crt0` asks for 48 KB of stack: a 40
  KB frame runs off the data area with `elf2mod`'s default 3 KB.

### Level 3: real interoperability

Real Microware objects and libraries, converted by `rof2elf` (§6), and OS-9 itself, through
`cdirun` (§9), on CD-i Emulator's CD-i 605 and on a real CD-i 605 player. Microware's files are
the user's own (`MWLIB=…`).

- **Without OS-9:** `make check-mw MWLIB=…` converts the local `cstart.r`, `clib.l` and `sys.l`
  with `rof2elf` and runs `mwtests/` in the Level 2 emulator. The test calls `strlen`, `atoi`,
  `strcmp`, `strcpy`, `strcat`, `sprintf`, `sscanf`, `toupper`, `index` and `atol`; Microware's
  `qsort` calls back a GCC comparator; and GCC's own `memcpy` for a struct copy goes to `clib`'s
  (with `-mbuiltin=os9call`).
- **On OS-9 itself:** `make check-os9 MWLIB=… CDIRUN=…` builds `mwtests/` with `-DREAL_OS9`,
  which also checks `malloc`/`free`, a file written with `fprintf` and read back with `fgets` (an OS-9
  line, ending in `'\r'`), and `atof` returning a double in d0:d1, printed with `%f` through the
  math trap; `stkchk.c` checks the stack against the process's own and watches `_stbot` go down as
  the stack grows; `newline.c` checks the bytes Microware's `sprintf` writes for a GCC format with
  `\n` and `\l`, and writes two lines with `\n` that Microware's `fgets` reads back as two lines
  (built without `-mos9newline` it fails). The modules are linked with the original `cstart.r`
  startup (GNU ld with `test/l68cmp/mod.lds`, then `elf2mod`), and `cdirun` copies them, loads
  and runs them, and reads the exit status, the failure mask. The OS-9 shell doesn't report an
  exit status of 1 (error `000:001`, "Process has aborted"), so the masks start at bit 1.
- **Mixed, on OS-9 itself:** `make check-os9mix MWLIB=… CDIRUN=… OS9_CCFLAGS=-t=/r512`.
  `mixtests/mwside.c` (K&R) is compiled by Microware C 3.2 on the CD-i 605 (`cc -r`),
  `gccside.c` by GCC `-mos9call`, and the two are linked by Microware's `cc`/`l68` on OS-9 (the
  GCC object through `elf2rof`) and by GNU ld on the PC (`mwside.r` copied up and through
  `rof2elf`, with `math.l` for C 3.2's `_T$DCmp`), then run there. GCC calls 21 Microware
  functions (int, double, pointer, char/short/unsigned, float-as-double, struct arguments in every
  position; char, short, unsigned char, pointer, float, double and long returns), which check what
  arrived; Microware code calls GCC functions back, directly, through a pointer and a variadic one
  (positional `va_arg`), and passes float variables, which C 3.2 widens to double (`_T$FtoD`), to
  GCC functions declared with `double` ("Widened prototypes", §4), first in d0:d1 and after an
  int on the stack. A build declaring one function's float argument unwidened fails exactly that
  check. GCC's side needs no libgcc, so `l68` links it alone. Struct returns are left out (C 3.2's
  static buffer and `-mos9call`'s a0 don't mix, §4).
- **The `-mos9stkchk` overflow path:** `mwtests/stkover.c` recurses until `cstart.r`'s
  `_stkcheck` stops it with "**** Stack Overflow ****"; `check-os9` expects its exit status from
  `mwtests/stkover.status`. That status is 2 (`000:002`), not the 0x101 `_stkcheck` pushes:
  Microware's `_exit` takes its argument in d0, which still holds the path number of the
  message's `I$WritLn`. A Microware quirk, which the test records.
- **newlib on OS-9:** `make check-os9newlib` builds `nltests/` with `-DREAL_OS9` and newlib's OS-9
  runtime (`-specs=os9.specs`) in both multilibs and runs it there: besides the Level 2 checks
  (and d2–d7/a2–a5 after `longjmp`), output, a file written and read back, and the time (the
  player's clock must be set).
- **`-mos9math`:** `make check-os9math` runs `os9tests/fpmath.c` (exact results bit for bit,
  comparisons, conversions, NaNs) and `os9tests/fnmath.c` (`sin` … `pow`, within 1E-13) with
  libgcc and libm, and with `-mos9math` in both multilibs.
- **A CD-i Emulator difference:** `move.l %sp,-(%sp)` pushes the original stack pointer on the
  68000 and on a real 68070, but the decremented one on CD-i Emulator's 68070. The tests avoid the
  instruction (GCC doesn't emit it).
- **Linking compared with `l68`:** `test/l68cmp/run.sh` links a test program with Microware's
  linker (Ultra C's `l68`, or Microware C 3.2's under vDos via `vdos.bat`) and the same ROFs
  with `rof2elf`, GNU ld and `elf2mod`, and compares the program and `.stb` symbol modules (§6).
- **`rof2elf`/`elf2rof` round trips:** `test/l68cmp/run.sh` converts `cstart.r`, `clib.l` and a
  test program ROF → ELF → ROF; Ultra C's `l68` and Microware C 3.2's under vDos link the same
  module from them as from the originals, byte for byte.
- **GCC code linked by `l68`:** `make check-l68 L68=…` converts the Level 2 tests and libgcc with
  `elf2rof`, links them with `l68` (with `-a` for the far-call test) and runs them as modules.
  With `MWLIB=…`, the Level 3 tests too, linked with Microware's original `clib.l`; `cstart.r`
  goes through `rof2elf` and back without its `__os9_*` symbols, so it isn't a second root psect
  (the harness's `crt0` is the entry, as with `check-mw`).

### Where tests live

Tests live under `test/` in this repository, outside `src/`: the `Dockerfile` copies `src/` into
the build, and tests don't belong in the image.

## 12. Open questions

- **GCC 17:** porting the fork to current mainline (§2).
- **C++:** enabling it in the toolchain build (`--enable-languages=c,c++`), where the C++ parts of
  §4 (mangling, member functions) and their Level 1 tests apply, and building libstdc++ with
  `-mos9call`, with `stackcall` on the unwinder interfaces.
- **A pragma for Microware declarations:** `#pragma os9call push` / `#pragma os9call pop`, giving
  every function declared in between the `os9call` attribute (through `m68k_insert_attributes`,
  as rs6000 does with `#pragma longcall`), for prototyped headers only GCC reads, which could then
  be wrapped whole around an `#include`. It wouldn't replace `_OS9PROTO` in headers shared with
  Microware C 3.2.
- **All-long offsets** (C 3.2's `-k=…l`, Ultra C's `-tp=…ld`/`…lc`): a6-relative data and code
  references as 32-bit offsets for a whole program. Long data could reuse the `remote` machinery
  (an option making all of a file's data remote); long code could use `bsr.l` on the 68020 and a
  32-bit PC-relative sequence on the 68000 (`move.l #target-*,dN` + `jsr (pc,dN.l)`, as
  `cstart.r` does), which would also lift the ±32 KB limit on branches within a function (§6).
  How Ultra C and C 3.2's `c68` handle long code offsets is to be checked first.
- **The math module's errors:** the *OS-9 Technical Manual* says the math module returns
  ±infinity or 0 before trapping, so an `F$STrap` TRAPV handler resuming after the `trapv` could
  give IEEE-like results instead of ending the program.
- **No FPU multilib:** a 68020/68881 multilib would follow `t-mlibs`' CPU multilibs, which
  `t-elfos9` replaces.
- **Windows packaging:** the Canadian cross in the Docker build, the zip with its short-names batch
  file (§8), then a CI artifact next to the Linux image (perhaps a `.msi` installer later).
- **Features without a run-time test:** FPU register saves under `-m68881`; `os9call` and
  `_OS9PROTO` declarations used without `-mos9call`; odd-sized structs of 2, 5, 6 and 7 bytes (1
  and 3 are tested); `long double` and `_Complex` on the stack and returned via a0; struct return
  through a function pointer; the exclusion of interrupt handlers; the 68881 `setjmp`/`longjmp`
  variants; a double as the second argument of a variadic call to a Microware library function
  (on the stack, not in d1). CI runs no tests.
- **An upstream latent bug:** an `interrupt_handler` function with an FPU and a frame of 32 KB or
  more restores its FPU registers through a1 after restoring a1. OS-9 convention functions avoid
  it (FPU registers first, a1 last); interrupt handlers are left unchanged to keep code built
  without the flag identical.
- **Not supported:** C 3.2's adhesive object modules (`-bg`) and `-to=os9k` (OS-9000).

### Known minor faults

None affects code built in the usual way:

- **`elf2rof`, weak definitions** become ordinary ROF definitions (ROF has no weak symbols), so
  two objects defining the same weak symbol (newlib's weak defaults, for example) make `l68`
  report duplicate symbols.
- **`elf2rof`, alignment above 2** (`.balign 4` in `.rodata` or `.data`) is kept within a psect,
  but `l68` places psects at even addresses only, so the final module doesn't guarantee it. The
  68000 needs no more than 2.
- **`rof2elf`, remote common definitions** (type 0x0102) become ordinary ELF common symbols,
  placed with the near data in the 64 KB a6 window instead of with the remote data.
- **`elf2mod`, absolute code-to-code references** (`R_68K_32` or `R_68K_16` from `.text` to
  `.text`) from hand-written assembly keep their link-time addresses, where `l68` writes module
  offsets; references from converted ROF code (`dc.w Init` in a driver's entry table) get module
  offsets, as with `l68`.
- **`elf2mod -g`, C 3.2 style:** flag 0x2000 goes on every symbol that a relocation refers to.
  With `ld -q`, GCC objects keep relocations against their own global symbols, so more symbols
  get it than "referred to by another psect" (`l68`) would give. It only matters when comparing
  `.stb` files byte for byte.
- **The Level 2 harness** doesn't check a module's type and language, or that its initialized
  data and references lie within the module and data area; and in 68040 mode it rejects word
  and long accesses at odd addresses, which the 68020 and later allow.
- **The test Makefile** doesn't rebuild when binutils (`as`, `ld`) change; clean the build
  directory after rebuilding them.

## 13. References

- Microware OS-9 manuals, hosted by ICDIA: <https://www.icdia.co.uk/microware/index.html>
  - *OS-9 C Language User Manual*: <https://www.icdia.co.uk/microware/77165104.pdf>
    (chapter 2 "Compiler Implementation", chapter 3 "Compiler Organization")
  - *OS-9 Assembler/Linker User Manual*: <https://www.icdia.co.uk/microware/77165106.pdf>
    (chapter 3 "Relocatable Program Sections", section "Relocatable Object File Format";
    chapter 6 "The Linker"; chapter 7 "OS-9 Programming Techniques")
  - *OS-9 C Compiler Version 3.2 Release Notes*: <https://www.icdia.co.uk/microware/os9ccmp.pdf>
  - *OS-9/68000 User-State Debugger* (Appendix A: symbol table module format):
    <https://www.icdia.co.uk/microware/userdbg.pdf>
- Microware LP's DMCA notice of 5 August 2026:
  <https://github.com/github/dmca/blob/master/2026/08/2026-08-05-microware.md>
- GCC mainline mirror: <https://github.com/gcc-mirror/gcc> (base tag `releases/gcc-11.1.0`)
- GCC AI policy: <https://gcc.gnu.org/ai-policy.html>; GNU "legally significant" changes:
  <https://www.gnu.org/prep/maintain/html_node/Legally-Significant.html>
- CD-i Emulator, by CD-i Fan: <https://www.cdiemu.org>
- Andreas Bischoff's OS-9 GCC cross-compiler pages (original host offline; 2001 Wayback snapshots):
  <https://web.archive.org/web/20010428184208/http://prt.fernuni-hagen.de:80/~bischoff/os9cross_e.html>,
  <https://web.archive.org/web/20010526164545/http://prt.fernuni-hagen.de:80/~bischoff/os9cross/hunt.html>,
  <https://web.archive.org/web/20010525130326/http://prt.fernuni-hagen.de:80/~bischoff/os9cross/howto_e.txt>,
  <https://web.archive.org/web/20010524172023/http://prt.fernuni-hagen.de:80/~bischoff/os9cross/gcccross.faq>
- This toolchain's GCC fork: <https://github.com/cdifan/gcc> (branch `11.1.0-os9` is Murachue's);
  Murachue's original repositories: <https://github.com/murachue/gcc>,
  <https://github.com/murachue/binutils-gdb>, <https://github.com/murachue/newlib-cygwin>,
  <https://github.com/murachue/elf2mod>
- GCC 1.37.1 OS-9 port by T. Shinohara and A. Seyama, on the "CDISC 4 Freeware" CD-i developer
  disc (April 1993), whose image is hosted by ICDIA: <https://www.icdia.co.uk/sw_disc/index.html>
- Walter Hunt's OS-9 GCC 2.6.2 cross compiler with ROF-capable binutils 2.5.2,
  `gcc-sun4-os9-2.6.2.src.tar.gz` (11,133,441 bytes, SHA-256
  `7b93f5df50d1017c0aead26e06e43769dc4f7cf6cb9502db57369d897aa5872e`):
  - mirror: <https://www.cdiemu.org/download/gcc-sun4-os9-2.6.2.src.tar.gz> (not linked from the
    download page)
  - original, now offline:
    `ftp://os9archive.rtsi.com/OS9/OSK/GCC/SRC/gcc-sun4-os9-2.6.2.src.tar.gz`. The FTP archive
    appears to have been retired around 2015, and the host now serves only RTSI's company site.
  - discussion: [CDinteractive forum thread][cdinteractive-os9-gcc]

[cdinteractive-os9-gcc]: http://www.cdinteractive.co.uk/forums/cdinteractive/viewtopic.php?t=2629
