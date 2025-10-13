#!/bin/bash
set -Eeuo pipefail

# installs vllm and dependencies in runtime stage
# expects VIRTUAL_ENV, CUDA_MAJOR, VLLM_REPO, VLLM_COMMIT_SHA, VLLM_PREBUILT, VLLM_USE_PRECOMPILED env vars

# shellcheck source=/dev/null
source /opt/vllm/bin/activate

# build list of packages to install
INSTALL_PACKAGES=(
    nixl
    cuda-python
    'huggingface_hub[hf_xet]'
    /tmp/wheels/*.whl
)

# clone vllm repository
git clone "${VLLM_REPO}" /opt/vllm-source
git -C /opt/vllm-source config --system --add safe.directory /opt/vllm-source
git -C /opt/vllm-source fetch --depth=1 origin "${VLLM_COMMIT_SHA}" || true
git -C /opt/vllm-source checkout -q "${VLLM_COMMIT_SHA}"

# detect if prebuilt wheel exists
WHEEL_URL=$(pip install \
    --no-cache-dir \
    --no-index \
    --no-deps \
    --find-links "https://wheels.vllm.ai/${VLLM_COMMIT_SHA}/vllm/" \
    --only-binary=:all: \
    --pre vllm \
    --dry-run \
    --disable-pip-version-check \
    -qqq \
    --report - \
    2>/dev/null | jq -r '.install[0].download_info.url')

if [ "${VLLM_PREBUILT}" = "1" ]; then
    if [ -z "${WHEEL_URL}" ]; then
        echo "VLLM_PREBUILT set but no platform compatible wheel exists for: https://wheels.vllm.ai/${VLLM_COMMIT_SHA}/vllm/"
        exit 1
    fi
    INSTALL_PACKAGES+=("${WHEEL_URL}")
    rm /opt/warn-vllm-precompiled.sh
else
    if [ "${VLLM_USE_PRECOMPILED}" = "1" ] && [ -n "${WHEEL_URL}" ]; then
        echo "Using precompiled binaries and shared libraries for commit: ${VLLM_COMMIT_SHA}."
        export VLLM_USE_PRECOMPILED=1
        export VLLM_PRECOMPILED_WHEEL_LOCATION="${WHEEL_URL}"
        INSTALL_PACKAGES+=(-e /opt/vllm-source)
        /opt/warn-vllm-precompiled.sh
        rm /opt/warn-vllm-precompiled.sh
    else
        echo "Compiling fully from source. Either precompile disabled or wheel not found in index from main."
        unset VLLM_USE_PRECOMPILED VLLM_PRECOMPILED_WHEEL_LOCATION || true
        INSTALL_PACKAGES+=(-e /opt/vllm-source)
        rm /opt/warn-vllm-precompiled.sh
    fi
fi

# add nvidia-nccl
INSTALL_PACKAGES+=("nvidia-nccl-cu12>=2.26.2.post1")

# install all packages in one command
uv pip install "${INSTALL_PACKAGES[@]}"

# cleanup
rm -rf /tmp/wheels
