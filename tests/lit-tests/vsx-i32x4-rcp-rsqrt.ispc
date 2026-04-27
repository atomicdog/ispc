// Verify that vsx-i32x4 emits native VSX reciprocal-estimate instructions
// (xvresp, xvrsqrtesp) plus a Newton-Raphson refinement using xvmaddasp,
// rather than the scalar-fallback lane-by-lane sequence the parent generic
// target produces.

// RUN: %{ispc} %s --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s

// REQUIRES: PPC64_ENABLED && LINUX_ENABLED

// CHECK-LABEL: test_rcp
// CHECK: xvresp
// CHECK: xvmaddasp

export void test_rcp(uniform float src[], uniform float dst[]) {
    dst[programIndex] = rcp(src[programIndex]);
}

// CHECK-LABEL: test_rsqrt
// CHECK: xvrsqrtesp
// CHECK: xvmaddasp

export void test_rsqrt(uniform float src[], uniform float dst[]) {
    dst[programIndex] = rsqrt(src[programIndex]);
}

// rcp_fast / rsqrt_fast are tested in a separate file because CHECK-NOT
// for "xvmaddasp" spans to the next CHECK-LABEL, which would conflict
// with the FMA-using full-precision variants above when emitted in the
// same translation unit.
