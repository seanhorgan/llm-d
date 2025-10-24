#!/bin/bash
set -Eeu

# installs base packages, EPEL/universe repos, and CUDA repository
#
# Required environment variables:
# - PYTHON_VERSION: Python version to install (e.g., 3.12)
# - CUDA_MAJOR: CUDA major version (e.g., 12)
# - TARGETOS: Target OS - either 'ubuntu' or 'rhel' (default: rhel)

TARGETOS="${TARGETOS:-rhel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# source shared utilities (check script dir first, fallback to /tmp for docker builds)
UTILS_SCRIPT="${SCRIPT_DIR}/../common/package-utils.sh"
[ ! -f "$UTILS_SCRIPT" ] && UTILS_SCRIPT="/tmp/package-utils.sh"
if [ ! -f "$UTILS_SCRIPT" ]; then
    echo "ERROR: package-utils.sh not found" >&2
    exit 1
fi
# shellcheck source=docker/scripts/cuda/common/package-utils.sh
source "$UTILS_SCRIPT"

DOWNLOAD_ARCH=$(get_download_arch)

# install jq first (required to parse package mappings)
if [ "$TARGETOS" = "ubuntu" ]; then
    apt-get update -qq
    apt-get install -y jq
elif [ "$TARGETOS" = "rhel" ]; then
    dnf -q update -y
    dnf -q install -y jq
fi

# main installation logic
if [ "$TARGETOS" = "ubuntu" ]; then
    setup_ubuntu_repos
    mapfile -t INSTALL_PKGS < <(load_layered_packages ubuntu "builder-packages.json" "cuda")
    install_packages ubuntu "${INSTALL_PKGS[@]}"
    cleanup_packages ubuntu

elif [ "$TARGETOS" = "rhel" ]; then
    setup_rhel_repos "$DOWNLOAD_ARCH"
    mapfile -t INSTALL_PKGS < <(load_layered_packages rhel "builder-packages.json" "cuda")
    install_packages rhel "${INSTALL_PKGS[@]}"

    rpm --import https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox
    curl >/etc/yum.repos.d/mellanox_mlnx_ofed.repo https://linux.mellanox.com/public/repo/mlnx_ofed/24.10-0.7.0.0/rhel9.5/mellanox_mlnx_ofed.repo
    dnf install libnl3-devel \
        --enablerepo=temp-alma-appstream \
        --repofrompath=temp-alma-appstream,https://mirror.grid.uchicago.edu/pub/linux/alma/9/AppStream/x86_64/os/ \
        --enablerepo=temp-alma-baseos \
        --repofrompath=temp-alma-baseos,https://mirror.grid.uchicago.edu/pub/linux/alma/9/BaseOS/x86_64/os/ -qy --nogpgcheck

    dnf -q install -y --allowerasing \
        rdma-core-devel

    cleanup_packages rhel

else
    echo "ERROR: Unsupported TARGETOS='$TARGETOS'. Must be 'ubuntu' or 'rhel'." >&2
    exit 1
fi
