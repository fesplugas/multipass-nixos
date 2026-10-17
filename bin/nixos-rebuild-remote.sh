#!/usr/bin/env bash

set -e

VM_NAME=${VM_NAME:-nixos}
VM_USER=${VM_USER:-ubuntu}
VM_IP=$(multipass info "$VM_NAME" --format json | jq --raw-output ".info[\"$VM_NAME\"].ipv4[0]")

# The IP address and the host key change with every new instance.
export NIX_SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# The VM builds its own system. Only the evaluation runs on this machine.
nixos-rebuild switch \
  --target-host $VM_USER@$VM_IP \
  --build-host $VM_USER@$VM_IP \
  --elevate sudo \
  --flake '.#multipass-vm'
