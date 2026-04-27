;;  Copyright (c) 2026, Intel Corporation
;;
;;  SPDX-License-Identifier: BSD-3-Clause


;; sleef macro layer: declares Sleef_<func><width>_u<ulp><isa> as external
;; symbols and defines target-agnostic __sleef_<func><type_letter>
;; alwaysinline thunks that call them.  Mirrors the structure of the
;; companion `svml' macro layer.
;;
;; The user must link their final executable against -lsleef (or a
;; static libsleef.a) to resolve the Sleef_* symbols at link time.

;; sleef_define : declare Sleef_<func><suffix> and define __sleef_<func><tl>
;; $1 - type ("float" or "double")
;; $2 - sleef function suffix, e.g. "f8_u10avx2", "d4_u10avx2", "f4_u10vsx"
;; $3 - vector width in lanes (matches the ispc varying width)
;; $4 - type letter ("f" for float, "d" for double)
;;
;; Initial function set: sin, cos, exp, log, pow.  Additional
;; transcendentals (tan, asin, acos, atan, atan2, sinh/cosh/tanh,
;; expm1, log1p, exp2, exp10, log2, log10, asinh, acosh, atanh,
;; cbrt, erf, erfc, hypot, sqrt) follow the same template and land
;; in a width-coverage follow-up.
define(`sleef_define',`
declare <$3 x $1> @Sleef_sin$2(<$3 x $1>) nounwind readnone
declare <$3 x $1> @Sleef_cos$2(<$3 x $1>) nounwind readnone
declare <$3 x $1> @Sleef_exp$2(<$3 x $1>) nounwind readnone
declare <$3 x $1> @Sleef_log$2(<$3 x $1>) nounwind readnone
declare <$3 x $1> @Sleef_pow$2(<$3 x $1>, <$3 x $1>) nounwind readnone

define <$3 x $1> @__sleef_sin$4(<$3 x $1> %x) nounwind readnone alwaysinline {
  %r = call <$3 x $1> @Sleef_sin$2(<$3 x $1> %x)
  ret <$3 x $1> %r
}

define <$3 x $1> @__sleef_cos$4(<$3 x $1> %x) nounwind readnone alwaysinline {
  %r = call <$3 x $1> @Sleef_cos$2(<$3 x $1> %x)
  ret <$3 x $1> %r
}

define <$3 x $1> @__sleef_exp$4(<$3 x $1> %x) nounwind readnone alwaysinline {
  %r = call <$3 x $1> @Sleef_exp$2(<$3 x $1> %x)
  ret <$3 x $1> %r
}

define <$3 x $1> @__sleef_log$4(<$3 x $1> %x) nounwind readnone alwaysinline {
  %r = call <$3 x $1> @Sleef_log$2(<$3 x $1> %x)
  ret <$3 x $1> %r
}

define <$3 x $1> @__sleef_pow$4(<$3 x $1> %a, <$3 x $1> %b) nounwind readnone alwaysinline {
  %r = call <$3 x $1> @Sleef_pow$2(<$3 x $1> %a, <$3 x $1> %b)
  ret <$3 x $1> %r
}
')


;; sleef : per-ISA dispatcher.  Picks the right (sleef-suffix, width)
;; for the current target's ISA + WIDTH.  Initial scope: AVX2 width-8
;; (avx2-i32x8 single-precision).  Other ISAs / widths land as the
;; per-target .ll files gain a sleef(ISA) invocation.
define(`sleef',`
ifelse($1, `AVX2', `
  ifelse(WIDTH, `8', `
    sleef_define(float, f8_u10avx2, 8, f)
    ;; double-precision dispatch for varying-double on avx2-i32x8 is
    ;; half-width (Sleef_sind4_u10avx2) and needs a width-doubling
    ;; wrapper.  Out of scope for the initial prototype.
  ', `
    errprint(`ERROR: sleef() does not yet handle WIDTH='WIDTH` for ISA='$1`
')
    m4exit(`1')
  ')
', `
  errprint(`ERROR: sleef() does not yet handle ISA='$1`
')
  m4exit(`1')
')
')
