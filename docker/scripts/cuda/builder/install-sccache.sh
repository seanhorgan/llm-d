#!/bin/bash
set -Eeu

# installs sccache binary from github releases and verifies connectivity
#
# Required environment variables:
# - USE_SCCACHE: whether to install and configure sccache (true/false)

if [ "${USE_SCCACHE}" = "true" ]; then
    dnf install -y openssl-devel
    mkdir -p /tmp/sccache
    cd /tmp/sccache
    curl -sLO https://github.com/mozilla/sccache/releases/download/v0.10.0/sccache-v0.10.0-x86_64-unknown-linux-musl.tar.gz
    tar -xf sccache-v0.10.0-x86_64-unknown-linux-musl.tar.gz
    mv sccache-v0.10.0-x86_64-unknown-linux-musl/sccache /usr/local/bin/sccache
    cd /tmp
    rm -rf /tmp/sccache

    # shellcheck source=/dev/null
    source /usr/local/bin/setup-sccache

    # verify sccache works with a simple test
    echo "int main() { return 0; }" | sccache gcc -x c - -o /dev/null
    echo "sccache installation and S3 connectivity verified"
fi
