#!/bin/bash
set -Eeu

# installs vllm and dependencies in runtime stage
#
# Required environment variables:
# - VLLM_REPO: vLLM git repository URL
# - VLLM_COMMIT_SHA: vLLM commit SHA to checkout
# - VLLM_PREBUILT: whether to use prebuilt wheel (1/0)
# - VLLM_USE_PRECOMPILED: whether to use precompiled binaries (1/0)

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

# detect architecture and construct wheel URL
ARCH=$(uname -m)
case "${ARCH}" in
  aarch64)
    PLATFORM_TAG="manylinux2014_aarch64"
    ;;
  x86_64)
    PLATFORM_TAG="manylinux1_x86_64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

# try to find wheel with correct platform tag
WHEEL_INDEX="https://wheels.vllm.ai/${VLLM_COMMIT_SHA}/vllm/"
WHEEL_URL=$(curl -sL "${WHEEL_INDEX}" | grep -o "href=\"[^\"]*${PLATFORM_TAG}[^\"]*\"" | cut -d'"' -f2 | sed 's|^\.\./||' | head -1)

if [ -n "${WHEEL_URL}" ]; then
  # wheel is in parent directory relative to /vllm/ listing
  WHEEL_URL="https://wheels.vllm.ai/${VLLM_COMMIT_SHA}/${WHEEL_URL}"
  echo "Found wheel for ${PLATFORM_TAG}: ${WHEEL_URL}"
else
  echo "No wheel found for platform ${PLATFORM_TAG} at ${WHEEL_INDEX}"
fi

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

# debug: print desired package list
echo "DEBUG: Installing packages: ${INSTALL_PACKAGES[*]}"

# install all packages in one command with verbose output to prevent GHA timeouts
uv pip install -v "${INSTALL_PACKAGES[@]}"

# cleanup
rm -rf /tmp/wheels
