#!/bin/bash
set -Eeuo pipefail

# builds and installs gdrcopy from source
#
# Required environment variables:
# - USE_SCCACHE: whether to use sccache (true/false)

# shellcheck source=/dev/null
source /usr/local/bin/setup-sccache

git clone https://github.com/NVIDIA/gdrcopy.git
cd gdrcopy

if [ "${USE_SCCACHE}" = "true" ]; then
    export CC="sccache gcc" CXX="sccache g++"
fi
PREFIX=/usr/local DESTLIB=/usr/local/lib make lib_install

cp src/libgdrapi.so.2.* /usr/lib64/
ldconfig

cd ..
rm -rf gdrcopy

if [ "${USE_SCCACHE}" = "true" ]; then
    echo "=== gdrcopy build complete - sccache stats ==="
    sccache --show-stats
fi
