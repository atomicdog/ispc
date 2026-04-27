# Sleef integration design

Ref: [#3406 Integrate Sleef library](https://github.com/ispc/ispc/issues/3406)

This document captures the proposed integration of [Sleef](https://sleef.org/)
as a new `--math-lib=sleef` option in ispc, mirroring the existing SVML
plumbing.  It exists so the design can be discussed and refined before
significant code lands.

## Motivation

The default `--math-lib=ispc` path uses ispc's own polynomial implementations.
On a Power9 host running `--target=vsx-i32x4 -O2` the polynomial sin/cos/exp
chain auto-vectorizes cleanly to `xvmaddasp` / `xvmulsp` and is reasonable
performance.  Two real gaps remain that the polynomial path is unlikely to
close:

1.  **Function coverage.**  ispc lacks `exp2`, `exp10`, `log2`, `log10`,
    `log1p`, `asinh`, `acosh`, `atanh`, and `hypot` (as of 2026-04).  zephyr111
    has been adding these one by one (PRs #3772, #3778, #3786, #3796, #3811,
    ...) but several remain.  Sleef ships all of them today.

2.  **Full-range correctness for trig.**  ispc's `sin()` polynomial uses a
    single-precision range reduction (`x - floor(x*2/pi) * pi/2`).  This loses
    accuracy badly for `|x| > ~2^14`.  Sleef's `_u10` mode uses
    Cody-Waite/Payne-Hanek with multi-word pi/2 and is correctly rounded across
    the full IEEE-754 single-precision domain.

`--math-lib=svml` papers over both gaps on x86 today, but is unavailable for
ARM / RISC-V / PowerPC.  Sleef supports all of these natively and is dual
BSL-1.0 / Apache 2.0 licensed (compatible with ispc's BSD-3-Clause).

glibc `libmvec` was considered first; it does not currently ship for ppc64le
in any glibc release (verified in glibc 2.42 on Fedora 43 ppc64le -- zero
`_ZGV*` symbols in `libm.so.6`), so it cannot be the multi-arch story.

## Integration approach: library-linking, mirror SVML

Sleef offers two integration vectors today:

-   `SLEEF_BUILD_INLINE_HEADERS=ON` produces a per-ISA `sleefinline_<isa>.h`
    of `static inline` polynomials.  These are C source with C-level
    typedefs (`vfloat_avx2_sleef`, etc.); they are not directly consumable
    as ispc bitcode.
-   The standard library form: `libsleef.{a,so}` exports symbols named
    `Sleef_<func><width>_u<ulp><isa>` -- e.g.
    `Sleef_sinf8_u10avx2`, `Sleef_sind4_u35avx2`, `Sleef_sinf4_u10vsx`.
    These are ABI-stable and can be called from bitcode the same way
    `__svml_*` is called.

`SLEEF_ENABLE_LLVM_BITCODE` referenced in #3406 is a planned-but-not-yet-
implemented sleef feature; only the comment at sleef
`CMakeLists.txt:370` exists.  Until that lands, the library-linking
form is the only viable path.

Recommendation: **mirror the SVML model.**  ispc emits calls to
`__sleef_<func><type>` ABI-stable per-target wrappers; per-target builtin
bitcode declares those wrappers as thin shims around the matching
`Sleef_*` symbol; the user links against `libsleef` at their own link
time.  This matches the existing `svml_stubs` macro layer in
`builtins/svml.m4` and the existing `__math_lib == __math_lib_svml`
branches in `stdlib/stdlib.ispc`.

A future follow-up can replace the user-side library link with bundled
bitcode once sleef supplies it.

## ispc target -> sleef ISA / width mapping

| ispc target          | sleef ISA suffix | sleef vector width (float / double) |
|----------------------|------------------|-------------------------------------|
| sse2-i32x4           | `sse2`           | 4 / 2                               |
| sse4-i32x4           | `sse4`           | 4 / 2                               |
| sse4-i32x8           | `sse4`           | 4+4 / 2+2 (double-pumped)           |
| sse4-i8x16           | `sse4`           | (mask only, no transcendentals)     |
| sse4-i16x8           | `sse4`           | (mask only)                         |
| avx1-i32x4           | `sse4` (no avx float trans in sleef) | 4 / 2          |
| avx1-i32x8           | `avx`            | 8 / 4                               |
| avx2-i32x8           | `avx2`           | 8 / 4                               |
| avx2-i32x16          | `avx2`           | 8+8 / 4+4                           |
| avx512skx-x4 / x8    | `avx512f`        | 16/8 (lower lanes used)             |
| avx512skx-x16        | `avx512f`        | 16 / 8                              |
| avx512skx-x32 / x64  | `avx512f`        | 16+16 / 8+8 (double-pumped)         |
| neon-i32x4           | `advsimd` (aarch64) / `neon` (armv7) | 4 / 2       |
| neon-i32x8           | `advsimd`        | 4+4 / 2+2                           |
| vsx-i32x4            | `vsx`            | 4 / 2                               |
| vsx-i32x8            | `vsx`            | 4+4 / 2+2                           |
| rvv-x4               | (not yet in sleef stable; rvv is in development) | -- |
| wasm-i32x4           | (no sleef wasm)  | --                                  |

Mask-only widths (sse4-i8x16, etc.) don't need transcendental support --
they fall through to the parent target's stdlib.

## File-by-file changes

### Compiler-side

1.  **`src/ispc.h`**: add `Math_Sleef` enum value to `Globals::MathLib`.

2.  **`src/args.cpp:830-841`**: parse `--math-lib=sleef`.

3.  **`src/preprocessor.cpp:333-341`**: define `ISPC_MATH_LIB_SLEEF_VAL`
    macro paralleling the existing `ISPC_MATH_LIB_*_VAL` set.

4.  **`src/ispc.cpp:1217`**: extend the math-lib validation check.
    Today: `Math_SVML && !ISPCTargetIsX86` errors.  Add: `Math_Sleef`
    requires `ISPC_SLEEF_ENABLED` cmake-time flag and a target with a
    sleef mapping (everything except wasm-* and the mask-only widths).

### Build-system

5.  **`CMakeLists.txt`**: add `option(ISPC_SLEEF_ENABLED ...)` defaulting
    OFF; when ON, add `ISPC_SLEEF_ENABLED` to `COMPILE_DEFINITIONS`.

6.  **`cmake/GenerateBuiltins.cmake`**: add `builtins/sleef.m4` to
    `M4_IMPLICIT_DEPENDENCIES`.

### Builtins

7.  **`builtins/sleef.m4` (new)**: parallel to `svml.m4`, defines
    `sleef_stubs(WIDTH, ULP, ISA_SUFFIX)` and `sleef_declare(...)`
    macros.  Generates declarations like

    ```llvm
    declare <8 x float> @Sleef_sinf8_u10avx2(<8 x float>) nounwind readnone
    define <8 x float> @__sleef_sinf(<8 x float> %x) nounwind readnone alwaysinline {
      %r = call <8 x float> @Sleef_sinf8_u10avx2(<8 x float> %x)
      ret <8 x float> %r
    }
    ```

    plus the same for `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`,
    `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `exp`, `expm1`,
    `exp2`, `exp10`, `log`, `log1p`, `log2`, `log10`, `pow`, `sqrt`,
    `cbrt`, `erf`, `erfc`, `hypot`, `fmod`.  The `_u35` variants are
    exposed as `__sleef_*_fast`.  Double-precision counterparts use
    `Sleef_*d<width/2>_u10<isa>`.

8.  **Per-target `.ll` files** (incrementally): each gets a
    `sleef_stubs(WIDTH, ULP, ISA_SUFFIX)` invocation matching its
    target.  Initial scope: `target-avx2-i32x8.ll` only (proves
    end-to-end on the most common x86 target).  Follow-up commits add
    avx512skx, sse4, neon, vsx variants.

### Stdlib

9.  **`stdlib/stdlib.ispc`**: add `else if (__math_lib == __math_lib_sleef)`
    branches in every transcendental wrapper (sin, cos, etc.), calling
    the matching `__sleef_*` symbol.

### Docs

10. **`docs/ispc.rst`**: document `--math-lib=sleef`, `-DISPC_SLEEF_ENABLED`,
    and the user-side `-lsleef` link requirement.

11. **`third-party-programs.txt`**: list sleef under user-link-time deps
    (no source bundled in ispc until a future bundled-bitcode follow-up).

## Open questions

-   **Default precision tier.**  Sleef's `_u10` is correctly-rounded;
    `_u35` is faster.  ispc's existing `--math-lib=svml` has no precision
    sub-toggle.  Recommendation: default to `_u10` (correctness),
    expose `--math-lib=sleef:fast` as opt-in to `_u35`.

-   **Width-doubling targets.**  For double-pumped widths (e.g.
    avx2-i32x16, vsx-i32x8), the per-half intrinsic must be called
    twice and merged.  The `unary4to8` macro from `util.m4` is already
    set up for this; new `unary4to8_call` / `binary4to8_call` variants
    that take an external symbol name would let `sleef_stubs` use the
    same machinery.

-   **Float16 transcendentals.**  Sleef supports half-precision math on
    architectures that have native FP16 (POWER9 `xscvsphp`,
    AVX-512 FP16, Arm v8.2-A FP16).  Out of scope for the initial
    prototype; punt to follow-up.

-   **Bundled vs user-link-time.**  Today's design assumes the user has
    sleef installed and adds `-lsleef` to their final link.  An
    optional bundled mode could ship a static sleef.a alongside ispc
    release artifacts -- adds ~2 MB per release tarball, removes the
    user-side install step.  Decide later based on user feedback.

-   **CI**.  Sleef is packaged in Fedora, Ubuntu (`libsleef-dev`), and
    Homebrew, so adding `apt install libsleef-dev` to the relevant CI
    workflows is one line.  RHEL via EPEL.  Not packaged in older
    Ubuntu LTS or Windows -- those CI jobs would skip
    `-DISPC_SLEEF_ENABLED=ON`.

## Initial PR scope

To keep review tractable, propose splitting into three PRs:

1.  **PR-1: scaffolding**.  `Math_Sleef` enum, `--math-lib=sleef`
    parsing, validation gate, `ISPC_SLEEF_ENABLED` cmake option,
    `builtins/sleef.m4`, `target-avx2-i32x8.ll` integration, stdlib
    branches for `sin`/`cos`/`exp`/`log`/`pow` (the common five).
    Roughly 300-400 LOC.  Lit test: assert the avx2-i32x8 asm now
    contains `bl Sleef_sinf8_u10avx2` when `--math-lib=sleef`.

2.  **PR-2: x86 width coverage**.  Wire sleef_stubs into all remaining
    x86 targets (avx2-i32x4, avx2-i32x16, avx1-*, avx512skx-*, sse4-*).
    Add full transcendental coverage (every function in the table).
    Roughly 200 LOC, mostly mechanical.

3.  **PR-3: non-x86 targets**.  Wire sleef_stubs into neon-* and
    vsx-* targets.  Roughly 150 LOC.  This is what unblocks the
    Power9 tier-1 transcendentals story.

Each PR is independently reviewable; PR-1 is the design-bearing one
that needs maintainer alignment.  PR-2 and PR-3 are mechanical
extensions once the shape is agreed upon.
