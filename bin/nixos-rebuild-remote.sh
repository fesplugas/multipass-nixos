#!/usr/bin/env bash

# Switch the running VM to the configuration in this repository. The script
# uses `multipass exec`, not SSH. The Multipass daemon holds the SSH key, so
# the user on this machine cannot log in with `ssh`.

set -euo pipefail

VM_NAME=${VM_NAME:-nixos}
REMOTE_DIR=${REMOTE_DIR:-/tmp/multipass-nixos}

cd "$(dirname "$0")/.."

# Copy the working tree, with uncommitted changes, to the VM. The VM builds its
# own system, so only the source files move. `multipass exec` sends stdin to
# the remote command. COPYFILE_DISABLE and --no-xattrs stop the macOS tar from
# adding `._*` files and Apple extended attributes. --touch sets the file times
# to the VM clock, which can run behind this machine.
echo "==> Copy the flake to $VM_NAME:$REMOTE_DIR" >&2
git ls-files --cached --others --exclude-standard -z \
  | COPYFILE_DISABLE=1 tar --create --no-xattrs --null --files-from=- --file=- \
  | multipass exec "$VM_NAME" -- bash -c \
    "rm --recursive --force '$REMOTE_DIR' && mkdir --parents '$REMOTE_DIR' && tar --extract --touch --directory '$REMOTE_DIR' --file=-"

echo "==> Switch $VM_NAME" >&2
multipass exec "$VM_NAME" -- sudo nixos-rebuild switch \
  --flake "$REMOTE_DIR#multipass-vm"
