#!/bin/bash
# google-crc32c with Google's CRC32C library, built from its newest release and bundled into a manylinux_2_28 wheel.
# PyPI publishes no ppc64le wheel.
set -euxo pipefail

PYTHON="/opt/python/$ABI-$ABI/bin/python3"
"$PYTHON" -m pip install cmake
CMAKE="$(dirname "$PYTHON")/cmake"

TAG="$(git ls-remote --tags --refs https://github.com/google/crc32c.git \
  | sed -nE 's#.*refs/tags/([0-9]+\.[0-9]+\.[0-9]+)$#\1#p' | sort -V | tail -1)"
[ -n "$TAG" ] || { echo "CRC32C release resolution failed"; exit 1; }
curl -fsSL "https://github.com/google/crc32c/archive/refs/tags/$TAG.tar.gz" | tar xz -C /tmp
# CRC32C's release declares a CMake minimum below 3.5, which CMake 4 no longer accepts without this policy floor.
"$CMAKE" -S "/tmp/crc32c-$TAG" -B /tmp/crc32c-build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DCRC32C_BUILD_TESTS=OFF -DCRC32C_BUILD_BENCHMARKS=OFF -DCRC32C_USE_GLOG=OFF -DCMAKE_INSTALL_PREFIX=/usr/local
"$CMAKE" --build /tmp/crc32c-build -j"$(nproc)"
"$CMAKE" --install /tmp/crc32c-build
ldconfig

CRC32C_INSTALL_PREFIX=/usr/local "$PYTHON" -m pip wheel --no-cache-dir --no-deps --no-binary google-crc32c \
  --wheel-dir=/tmp/wheels "google-crc32c==$VERSION"
if compgen -G '/tmp/wheels/*-none-any.whl' > /dev/null; then
  echo "google-crc32c built without its C extension"
  exit 1
fi
LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib auditwheel repair /tmp/wheels/*.whl --plat manylinux_2_28_ppc64le --wheel-dir=/output
