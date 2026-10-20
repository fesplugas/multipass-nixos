#!/usr/bin/env bash

# Switch the running VM to the configuration in this repository. The script
# uses `multipass exec`, not SSH. The Multipass daemon holds the SSH key, so
# the user on this machine cannot log in with `ssh`.

set -euo pipefail

VM_NAME=${VM_NAME:-nixos}
REMOTE_DIR=${REMOTE_DIR:-/tmp/multipass-nixos}

cd "$(dirname "$0")/.."

# Print a section header. A blank line separates the sections and the whole
# `==> ...` line is bold blue when stderr is a terminal. Set NO_COLOR to keep
# it plain.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  color_start=$'\033[1;34m'
  color_end=$'\033[0m'
else
  color_start=
  color_end=
fi

log_started=
log() {
  if [ -n "$log_started" ]; then
    echo >&2
  fi
  log_started=1
  printf '%s==> %s%s\n' "$color_start" "$*" "$color_end" >&2
}

# The flake reads only these files: flake.nix, its lock, and the
# configuration.nix that flake.nix imports. Keep this list in sync with the
# local imports when the flake gains one. bin/build.sh ships the same set.
FLAKE_FILES=(flake.nix flake.lock configuration.nix)

# Copy the flake, with uncommitted changes, to the VM. The VM builds its own
# system, so only the source files move. `multipass exec` sends stdin to the
# remote command. COPYFILE_DISABLE and --no-xattrs stop the macOS tar from
# adding `._*` files and Apple extended attributes. --touch sets the file times
# to the VM clock, which can run behind this machine.
log "Copy the flake to $VM_NAME:$REMOTE_DIR"
printf '  - %s\n' "${FLAKE_FILES[@]}" >&2
COPYFILE_DISABLE=1 tar --create --no-xattrs --file=- "${FLAKE_FILES[@]}" \
  | multipass exec "$VM_NAME" -- bash -c \
    "rm --recursive --force '$REMOTE_DIR' && mkdir --parents '$REMOTE_DIR' && tar --extract --touch --directory '$REMOTE_DIR' --file=-"

log "Switch $VM_NAME"
multipass exec "$VM_NAME" -- sudo nixos-rebuild switch \
  --flake "$REMOTE_DIR#multipass-vm"
