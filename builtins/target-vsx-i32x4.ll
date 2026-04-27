;;
;; target-vsx-i32x4.ll
;;
;;  Copyright(c) 2026 Intel
;;
;;  SPDX-License-Identifier: BSD-3-Clause
;;
;; Native VSX overrides for the most expensive operations the generic
;; parent chain otherwise scalarizes.  Other widths (vsx-i8x16, i8x32,
;; i16x8, i16x16, i32x8) still fall through to generic-* until they
;; grow their own per-width files.

define(`WIDTH',`4')
define(`MASK',`i32')
define(`ISA',`VSX')

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fast-math / FTZ-DAZ
;;
;; PowerPC FPSCR has a non-IEEE bit (NJ) whose semantics vary across
;; CPU generations: POWER8 honors it for some VSX scalar paths,
;; POWER9+ effectively ignores it.  Until per-CPU stdlib variants
;; exist these are no-op placeholders so programs that call them link.

define void @__fastmath() nounwind alwaysinline {
  ret void
}

define i32 @__set_ftz_daz_flags() nounwind alwaysinline {
  ret i32 0
}

define void @__restore_ftz_daz_flags(i32 %oldVal) nounwind alwaysinline {
  ret void
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; mask operations
;;
;; PowerPC has no single-instruction movmsk equivalent.  Express the
;; pack as trunc-to-<4 x i1> + bitcast-to-i4 so the LLVM IR matches the
;; canonical mask-pack idiom the rest of the compiler emits; this
;; preserves IR-level optimization patterns that downstream tests pin
;; on, while letting the PowerPC backend select an efficient lowering.

define i64 @__movmsk(<4 x i32>) nounwind readnone alwaysinline {
  %as_bool = trunc <4 x i32> %0 to <4 x i1>
  %as_i4 = bitcast <4 x i1> %as_bool to i4
  %as_i64 = zext i4 %as_i4 to i64
  ret i64 %as_i64
}

define i1 @__any(<4 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<4 x i32> %0)
  %cmp = icmp ne i64 %m, 0
  ret i1 %cmp
}

define i1 @__all(<4 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<4 x i32> %0)
  %cmp = icmp eq i64 %m, 15
  ret i1 %cmp
}

define i1 @__none(<4 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<4 x i32> %0)
  %cmp = icmp eq i64 %m, 0
  ret i1 %cmp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; rcp / rsqrt
;;
;; VSX provides single-precision reciprocal and reciprocal-sqrt
;; estimates accurate to ~12 bits.  One Newton-Raphson iteration
;; refines to full single-precision (~24 bits).
;;
;;   rcp   N-R: x_{n+1} = x_n * (2 - d * x_n)
;;   rsqrt N-R: x_{n+1} = 0.5 * x_n * (3 - d * x_n^2)

declare <4 x float> @llvm.ppc.vsx.xvresp(<4 x float>) nounwind readnone
declare <4 x float> @llvm.ppc.vsx.xvrsqrtesp(<4 x float>) nounwind readnone

define <WIDTH x float> @__rcp_varying_float(<WIDTH x float> %d) nounwind readnone alwaysinline {
  %x0 = call <4 x float> @llvm.ppc.vsx.xvresp(<4 x float> %d)
  %dx0 = fmul <4 x float> %d, %x0
  %two_minus = fsub <4 x float> <float 2.0, float 2.0, float 2.0, float 2.0>, %dx0
  %x1 = fmul <4 x float> %x0, %two_minus
  ret <4 x float> %x1
}

define <WIDTH x float> @__rcp_fast_varying_float(<WIDTH x float> %d) nounwind readnone alwaysinline {
  %x0 = call <4 x float> @llvm.ppc.vsx.xvresp(<4 x float> %d)
  ret <4 x float> %x0
}

define float @__rcp_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <4 x float> undef, float %d, i32 0
  %vr = call <4 x float> @__rcp_varying_float(<4 x float> %v)
  %r = extractelement <4 x float> %vr, i32 0
  ret float %r
}

define float @__rcp_fast_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <4 x float> undef, float %d, i32 0
  %vr = call <4 x float> @__rcp_fast_varying_float(<4 x float> %v)
  %r = extractelement <4 x float> %vr, i32 0
  ret float %r
}

define <WIDTH x float> @__rsqrt_varying_float(<WIDTH x float> %d) nounwind readnone alwaysinline {
  %x0 = call <4 x float> @llvm.ppc.vsx.xvrsqrtesp(<4 x float> %d)
  %x0_2 = fmul <4 x float> %x0, %x0
  %d_x0_2 = fmul <4 x float> %d, %x0_2
  %three_minus = fsub <4 x float> <float 3.0, float 3.0, float 3.0, float 3.0>, %d_x0_2
  %half_x0 = fmul <4 x float> %x0, <float 0.5, float 0.5, float 0.5, float 0.5>
  %x1 = fmul <4 x float> %half_x0, %three_minus
  ret <4 x float> %x1
}

define <WIDTH x float> @__rsqrt_fast_varying_float(<WIDTH x float> %d) nounwind readnone alwaysinline {
  %x0 = call <4 x float> @llvm.ppc.vsx.xvrsqrtesp(<4 x float> %d)
  ret <4 x float> %x0
}

define float @__rsqrt_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <4 x float> undef, float %d, i32 0
  %vr = call <4 x float> @__rsqrt_varying_float(<4 x float> %v)
  %r = extractelement <4 x float> %vr, i32 0
  ret float %r
}

define float @__rsqrt_fast_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <4 x float> undef, float %d, i32 0
  %vr = call <4 x float> @__rsqrt_fast_varying_float(<4 x float> %v)
  %r = extractelement <4 x float> %vr, i32 0
  ret float %r
}
