// Verify that --cpu=pwr9 and --cpu=pwr10 are accepted, route to the
// VSX targets, and feed the right ISA generation through to the
// PowerPC backend.
//
// POWER9 introduced single-instruction VSX load/store (lxv, stxv)
// where POWER8 had to emit lxvd2x + xxswapd.  Detecting either of
// the single-instruction forms in the asm proves the CPU bump took
// effect end-to-end (option parsing -> CPU selection ->
// LLVM target-features string).

// RUN: %{ispc} %s --cpu=pwr9 --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s -check-prefix=PWR9PLUS
// RUN: %{ispc} %s --cpu=power9 --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s -check-prefix=PWR9PLUS
// RUN: %{ispc} %s --cpu=pwr10 --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s -check-prefix=PWR9PLUS
// RUN: %{ispc} %s --cpu=power10 --target=vsx-i32x4 --arch=ppc64le --target-os=linux --nowrap -O2 --emit-asm -o - | FileCheck %s -check-prefix=PWR9PLUS

// REQUIRES: PPC64_ENABLED && LINUX_ENABLED

// PWR9PLUS: lxv {{[0-9]+}}, 0(
// PWR9PLUS: stxv {{[0-9]+}}, 0(
// PWR9PLUS-NOT: lxvd2x

export void rcp_test(uniform float src[], uniform float dst[]) {
    dst[programIndex] = rcp(src[programIndex]);
}
