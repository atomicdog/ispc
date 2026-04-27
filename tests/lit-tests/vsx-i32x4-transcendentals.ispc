// Verify that varying transcendentals compile cleanly on vsx-i32x4 and
// vsx-i32x8 via the default --math-lib=ispc polynomial path.
//
// glibc does not currently ship libmvec on ppc64le, and ispc errors out
// when --math-lib=svml is requested for a non-x86 target.  The default
// (Math_ISPC) is a portable polynomial implementation that LLVM's
// PowerPC backend auto-vectorizes to FMA-style VSX instructions
// (xvmaddasp / xvnmsubasp / xvmulsp / xvaddsp).
//
// This test pins three things:
//   - sin / cos / exp / log / pow all produce VSX-vectorized asm,
//   - the polynomial transcendental path stays linkable (no missing
//     __svml_* externs leaking through),
//   - the same source compiles cleanly at both i32x4 and i32x8 widths.

// RUN: %{ispc} %s --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s
// RUN: %{ispc} %s --target=vsx-i32x8 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s

// REQUIRES: PPC64_ENABLED && LINUX_ENABLED

// CHECK-LABEL: sin_v
// CHECK: xvmaddasp
// CHECK-NOT: bl __svml_

export void sin_v(uniform float a[], uniform float dst[]) {
    dst[programIndex] = sin(a[programIndex]);
}

// CHECK-LABEL: cos_v
// CHECK: xvmaddasp
// CHECK-NOT: bl __svml_

export void cos_v(uniform float a[], uniform float dst[]) {
    dst[programIndex] = cos(a[programIndex]);
}

// CHECK-LABEL: exp_v
// CHECK: xvmaddasp
// CHECK-NOT: bl __svml_

export void exp_v(uniform float a[], uniform float dst[]) {
    dst[programIndex] = exp(a[programIndex]);
}

// CHECK-LABEL: log_v
// CHECK: xvmaddasp
// CHECK-NOT: bl __svml_

export void log_v(uniform float a[], uniform float dst[]) {
    dst[programIndex] = log(a[programIndex]);
}

// CHECK-LABEL: pow_v
// CHECK: xvmaddasp
// CHECK-NOT: bl __svml_

export void pow_v(uniform float a[], uniform float b[], uniform float dst[]) {
    dst[programIndex] = pow(a[programIndex], b[programIndex]);
}
