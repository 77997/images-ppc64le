#!/bin/bash
# google-re2 for the Python of debian:trixie, built against Debian's RE2 and pybind11; Zuul's image installs
# libre2 at run time. PyPI publishes no ppc64le wheel.
set -euxo pipefail

apt-get update
apt-get install -y --no-install-recommends python3-dev python3-pip python3-venv build-essential pkg-config libre2-dev pybind11-dev
python3 -m venv /tmp/build
/tmp/build/bin/pip install --upgrade pip
/tmp/build/bin/pip wheel --no-cache-dir --no-deps --no-binary google-re2 --wheel-dir=/output "google-re2==$VERSION"
