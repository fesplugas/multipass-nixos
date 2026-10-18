#!/usr/bin/env bash

# Build the QCOW2 image in a Multipass builder VM and copy it to this directory.
# The steps are the same as the "Build" steps in the README. Every step can run
# again: the script creates the VM and installs Nix only when they are missing.

set -euo pipefail

BUILDER_NAME=${BUILDER_NAME:-builder}
BUILDER_CPUS=${BUILDER_CPUS:-4}
BUILDER_MEMORY=${BUILDER_MEMORY:-8G}
BUILDER_DISK=${BUILDER_DISK:-40G}
FLAKE_OUTPUT=${FLAKE_OUTPUT:-qcow2}

cd "$(dirname "$0")/.."

log() {
  echo "==> $*" >&2
}

builder_exec() {
  multipass exec "$BUILDER_NAME" -- "$@"
}

log "Check the builder VM"
if ! multipass info "$BUILDER_NAME" > /dev/null 2>&1; then
  multipass launch --name "$BUILDER_NAME" --cpus "$BUILDER_CPUS" --memory "$BUILDER_MEMORY" --disk "$BUILDER_DISK"
fi

# A stopped VM does not accept commands.
multipass start "$BUILDER_NAME"

# Do not redirect the output of `multipass exec` to /dev/null. The client hangs
# at full CPU. Capture the output with a command substitution instead.
log "Check Nix"
if [ -z "$(builder_exec bash -lc 'command -v nix || true')" ]; then
  builder_exec sh -c 'curl --proto "=https" --tlsv1.2 --silent --show-error --fail --location https://install.determinate.systems/nix | sh -s -- install --no-confirm'
fi

# The builder VM has no /dev/kvm, so QEMU uses software emulation. The build is
# slow, but it works. The image builder needs the `kvm` feature.
log "Check the kvm system feature"
if [ -z "$(builder_exec bash -c 'grep --no-messages "extra-system-features = kvm" /etc/nix/nix.custom.conf || true')" ]; then
  builder_exec sudo sh -c 'echo "extra-system-features = kvm" >> /etc/nix/nix.custom.conf'
  builder_exec sudo systemctl restart nix-daemon
fi

log "Copy the flake files"
builder_exec mkdir --parents nixos
multipass transfer flake.nix flake.lock configuration.nix "$BUILDER_NAME:nixos/"

# The build logs go to stderr, so the command substitution does not hide them.
log "Build .#$FLAKE_OUTPUT (this can take a long time)"
out_path=$(builder_exec bash -lc "cd nixos && nix build .#$FLAKE_OUTPUT --no-link --print-out-paths --print-build-logs")
image=$(builder_exec bash -lc "ls $out_path/*.qcow2")

log "Copy the image"
# Files in the Nix store are read-only, and the transfer keeps that mode. A
# read-only image from an earlier build makes the next transfer fail with
# "Permission denied", so remove it first and make the new copy writable.
rm --force "$(basename "$image")"
multipass transfer "$BUILDER_NAME:$image" .
chmod u+w "$(basename "$image")"
echo "Image: $PWD/$(basename "$image")"
