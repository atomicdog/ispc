;;
;; target-vsx-i32x8.ll
;;
;;  Copyright(c) 2026 Intel
;;
;;  SPDX-License-Identifier: BSD-3-Clause
;;
;; Native VSX implementations for the double-pumped 8-wide variant.
;; Each operation splits the <8 x ?> input into two <4 x ?> halves
;; with the unary4to8 helper from util.m4, runs the per-half VSX
;; intrinsic, and merges the result.

define(`WIDTH',`8')
define(`MASK',`i32')
define(`ISA',`VSX')

include(`util.m4')

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fast-math / FTZ-DAZ
;;
;; No-op placeholders; see target-vsx-i32x4.ll for the rationale.

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
;; Same canonical idiom as the i32x4 path, packing 8 lanes into i8.

define i64 @__movmsk(<8 x i32>) nounwind readnone alwaysinline {
  %as_bool = trunc <8 x i32> %0 to <8 x i1>
  %as_i8 = bitcast <8 x i1> %as_bool to i8
  %as_i64 = zext i8 %as_i8 to i64
  ret i64 %as_i64
}

define i1 @__any(<8 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<8 x i32> %0)
  %cmp = icmp ne i64 %m, 0
  ret i1 %cmp
}

define i1 @__all(<8 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<8 x i32> %0)
  %cmp = icmp eq i64 %m, 255
  ret i1 %cmp
}

define i1 @__none(<8 x i32>) nounwind readnone alwaysinline {
  %m = call i64 @__movmsk(<8 x i32> %0)
  %cmp = icmp eq i64 %m, 0
  ret i1 %cmp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; rcp / rsqrt -- split <8 x float> into two halves, each via the
;; matching VSX estimate intrinsic plus one Newton-Raphson iteration.
;;
;;   rcp   N-R: x_{n+1} = x_n * (2 - d * x_n)
;;   rsqrt N-R: x_{n+1} = 0.5 * x_n * (3 - d * x_n^2)

declare <4 x float> @llvm.ppc.vsx.xvresp(<4 x float>) nounwind readnone
declare <4 x float> @llvm.ppc.vsx.xvrsqrtesp(<4 x float>) nounwind readnone

define <8 x float> @__rcp_varying_float(<8 x float> %d) nounwind readnone alwaysinline {
  unary4to8(x0, float, @llvm.ppc.vsx.xvresp, %d)
  %dx0 = fmul <8 x float> %d, %x0
  %two_minus = fsub <8 x float>
    <float 2.0, float 2.0, float 2.0, float 2.0,
     float 2.0, float 2.0, float 2.0, float 2.0>, %dx0
  %x1 = fmul <8 x float> %x0, %two_minus
  ret <8 x float> %x1
}

define <8 x float> @__rcp_fast_varying_float(<8 x float> %d) nounwind readnone alwaysinline {
  unary4to8(ret, float, @llvm.ppc.vsx.xvresp, %d)
  ret <8 x float> %ret
}

define float @__rcp_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <8 x float> undef, float %d, i32 0
  %vr = call <8 x float> @__rcp_varying_float(<8 x float> %v)
  %r = extractelement <8 x float> %vr, i32 0
  ret float %r
}

define float @__rcp_fast_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <8 x float> undef, float %d, i32 0
  %vr = call <8 x float> @__rcp_fast_varying_float(<8 x float> %v)
  %r = extractelement <8 x float> %vr, i32 0
  ret float %r
}

define <8 x float> @__rsqrt_varying_float(<8 x float> %d) nounwind readnone alwaysinline {
  unary4to8(x0, float, @llvm.ppc.vsx.xvrsqrtesp, %d)
  %x0_2 = fmul <8 x float> %x0, %x0
  %d_x0_2 = fmul <8 x float> %d, %x0_2
  %three_minus = fsub <8 x float>
    <float 3.0, float 3.0, float 3.0, float 3.0,
     float 3.0, float 3.0, float 3.0, float 3.0>, %d_x0_2
  %half_x0 = fmul <8 x float> %x0,
    <float 0.5, float 0.5, float 0.5, float 0.5,
     float 0.5, float 0.5, float 0.5, float 0.5>
  %x1 = fmul <8 x float> %half_x0, %three_minus
  ret <8 x float> %x1
}

define <8 x float> @__rsqrt_fast_varying_float(<8 x float> %d) nounwind readnone alwaysinline {
  unary4to8(ret, float, @llvm.ppc.vsx.xvrsqrtesp, %d)
  ret <8 x float> %ret
}

define float @__rsqrt_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <8 x float> undef, float %d, i32 0
  %vr = call <8 x float> @__rsqrt_varying_float(<8 x float> %v)
  %r = extractelement <8 x float> %vr, i32 0
  ret float %r
}

define float @__rsqrt_fast_uniform_float(float %d) nounwind readnone alwaysinline {
  %v = insertelement <8 x float> undef, float %d, i32 0
  %vr = call <8 x float> @__rsqrt_fast_varying_float(<8 x float> %v)
  %r = extractelement <8 x float> %vr, i32 0
  ret float %r
}
