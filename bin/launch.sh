#!/usr/bin/env bash

# Launch the image that bin/build.sh made. Delete the previous VM with the
# same name first. Extra arguments go to `multipass launch`, for example
# `bin/launch.sh --cpus 4 --memory 8G`.

set -euo pipefail

VM_NAME=${VM_NAME:-nixos}
IMAGE=${IMAGE:-nixos-multipass.qcow2}

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
multipass launch "file://$PWD/$IMAGE" --name "$VM_NAME" "$@"
