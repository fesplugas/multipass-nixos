#!/usr/bin/env bash

# Launch the image that bin/build.sh made. Delete the previous VM with the
# same name first. Extra arguments go to `multipass launch`, for example
# `VM_MEMORY=8G bin/launch.sh`. The defaults are 40G disk, 4G memory and 2 CPUs.
# Set VM_DISK, VM_MEMORY or VM_CPUS to change them. Do not pass `--disk`,
# `--memory` or `--cpus` as extra arguments.

set -euo pipefail

VM_NAME=${VM_NAME:-nixos}
IMAGE=${IMAGE:-nixos-multipass.qcow2}
# The Multipass defaults (5G disk, 1G memory) are too small to evaluate and
# build the flake. The build stops with "No space left on device" or with an
# out-of-memory kill.
VM_DISK=${VM_DISK:-40G}
VM_MEMORY=${VM_MEMORY:-4G}
VM_CPUS=${VM_CPUS:-2}

cd "$(dirname "$0")/.."

if [ ! -f "$IMAGE" ]; then
  echo "Image not found: $PWD/$IMAGE. Run bin/build.sh first." >&2
  exit 1
fi

if multipass info "$VM_NAME" > /dev/null 2>&1; then
  echo "==> Delete the existing VM $VM_NAME" >&2
  multipass delete --purge "$VM_NAME"
fi

echo "==> Launch $VM_NAME" >&2
multipass launch "file://$PWD/$IMAGE" --name "$VM_NAME" --disk "$VM_DISK" --memory "$VM_MEMORY" --cpus "$VM_CPUS" "$@"
