// Verify that --math-lib=sleef on avx2-i32x8 routes the user-visible
// sin/cos/exp/log/pow calls through ispc's __sleef_<func>f thunks down
// to the Sleef_<func>f8_u10avx2 external symbols (which the user must
// resolve at their own link time by linking -lsleef).

// RUN: %{ispc} %s --target=avx2-i32x8 --math-lib=sleef --nowrap -O2 --emit-asm -o - | FileCheck %s

// REQUIRES: X86_ENABLED && ISPC_SLEEF_ENABLED

// CHECK-LABEL: t_sin
// CHECK: callq Sleef_sinf8_u10avx2

export void t_sin(uniform float src[], uniform float dst[]) {
    dst[programIndex] = sin(src[programIndex]);
}

// CHECK-LABEL: t_cos
// CHECK: callq Sleef_cosf8_u10avx2

export void t_cos(uniform float src[], uniform float dst[]) {
    dst[programIndex] = cos(src[programIndex]);
}

// CHECK-LABEL: t_exp
// CHECK: callq Sleef_expf8_u10avx2

export void t_exp(uniform float src[], uniform float dst[]) {
    dst[programIndex] = exp(src[programIndex]);
}

// CHECK-LABEL: t_log
// CHECK: callq Sleef_logf8_u10avx2

export void t_log(uniform float src[], uniform float dst[]) {
    dst[programIndex] = log(src[programIndex]);
}

// CHECK-LABEL: t_pow
// CHECK: callq Sleef_powf8_u10avx2

export void t_pow(uniform float a[], uniform float b[], uniform float dst[]) {
    dst[programIndex] = pow(a[programIndex], b[programIndex]);
}
