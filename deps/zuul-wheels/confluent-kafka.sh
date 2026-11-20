#!/bin/bash
# confluent-kafka with librdkafka of its own major and minor version, the newest patch release, built from source and
# bundled into a manylinux_2_28 wheel. PyPI publishes no ppc64le wheel, and AlmaLinux 8 has no librdkafka this new.
set -euxo pipefail

PYTHON="/opt/python/$ABI-$ABI/bin/python3"
yum install -y openssl-devel zlib-devel libzstd-devel lz4-devel cyrus-sasl-devel

SERIES="${VERSION%.*}"
LIBRDKAFKA="$(git ls-remote --tags --refs https://github.com/confluentinc/librdkafka.git \
  | sed -nE "s#.*refs/tags/v(${SERIES//./\\.}\.[0-9]+)\$#\1#p" | sort -V | tail -1)"
[ -n "$LIBRDKAFKA" ] || { echo "No librdkafka $SERIES release found"; exit 1; }
curl -fsSL "https://github.com/confluentinc/librdkafka/archive/refs/tags/v$LIBRDKAFKA.tar.gz" | tar xz -C /tmp
cd "/tmp/librdkafka-$LIBRDKAFKA"
./configure --prefix=/usr/local
make -j"$(nproc)"
make install
ldconfig
cd /

"$PYTHON" -m pip wheel --no-cache-dir --no-deps --no-binary confluent-kafka --wheel-dir=/tmp/wheels "confluent-kafka==$VERSION"
LD_LIBRARY_PATH=/usr/local/lib auditwheel repair /tmp/wheels/*.whl --plat manylinux_2_28_ppc64le --wheel-dir=/output
