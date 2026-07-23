#!/usr/bin/env bash
set -euo pipefail

work_dir="${WORK_DIR:-/home/valtos/rmx3630-port-work}"
build_dir="$work_dir/halium-rmx-build"
out_dir="${OUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/out/halium}"
tools_dir="$work_dir/halium-build-tools"
kernel_dir="$work_dir/kernel-volla-mt6789"

mkdir -p "$build_dir/downloads" "$out_dir"
if [[ ! -d "$tools_dir/.git" ]]; then
    git clone --depth 1 \
        https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git \
        "$tools_dir"
fi

kernel_link="$build_dir/downloads/kernel-volla-mt6789"
if [[ ! -e "$kernel_link" ]]; then
    ln -s "$kernel_dir" "$kernel_link"
fi

"$tools_dir/build.sh" -k -b "$build_dir" -o "$out_dir"
