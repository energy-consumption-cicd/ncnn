#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required}"

SRC=/project
BUILDS=/builds
JOBS=$(nproc)

# Steps of job linux-gcc, .github/workflows/linux-x64-cpu-gcc.yml:46-85 at tag 20250503 (305837fd).

mkdir -p "$BUILDS"

do_build() {
  local dir="$1"; shift
  mkdir -p "$BUILDS/$dir" && cd "$BUILDS/$dir"
  cmake "$@" "$SRC"
  cmake --build . -j "$JOBS"
}

do_test() {
  local dir="$1"
  cd "$BUILDS/$dir"
  ctest --output-on-failure -j "$JOBS"
}

case "$STAGE" in
  build_sse2)     do_build build-sse2    -DNCNN_AVX=OFF -DNCNN_AVX2=OFF -DNCNN_BUILD_TESTS=ON ;;
  test_sse2)      do_test  build-sse2 ;;
  build_shared)   do_build build-shared  -DNCNN_AVX2=ON -DNCNN_SHARED_LIB=ON ;;                 # no ctest upstream either
  build_avx2)     do_build build-avx2    -DNCNN_AVX2=ON -DNCNN_BUILD_TESTS=ON ;;
  test_avx2)      do_test  build-avx2 ;;
  build_avx)      do_build build-avx     -DNCNN_AVX2=OFF -DNCNN_AVX=ON -DNCNN_BUILD_TESTS=ON ;;
  test_avx)       do_test  build-avx ;;
  build_avx1_2)   do_build build-avx1-2  -DNCNN_AVX2=ON -DNCNN_AVX=ON -DNCNN_BUILD_TESTS=ON ;;
  test_avx1_2)    do_test  build-avx1-2 ;;
  build_noint8)   do_build build-noint8  -DNCNN_INT8=OFF -DNCNN_BUILD_TESTS=ON ;;
  test_noint8)    do_test  build-noint8 ;;
  *)
    echo "Unknown stage: $STAGE" >&2
    exit 1
    ;;
esac
