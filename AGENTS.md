# AGENTS.md

A Nix flake that builds a NixOS 26.05 QCOW2 image (aarch64) for Multipass. The
flake exposes `nixosConfigurations.multipass` (base), `multipass-vm` (base plus
the `qemu-efi` disk layout and bootloader) and `packages.aarch64-linux.qcow2`.

## Requirements

- Multipass on an Apple Silicon Mac.
- Nix on macOS cannot build `aarch64-linux`. Build or switch from inside a
  Multipass VM, never on the host.

## Rebuild

The two VMs that matter:

| VM | Purpose |
| --- | --- |
| `builder` | Builds the QCOW2 image. Never runs the configuration. |
| `nixos` | The running VM that `bin/nixos-rebuild-remote.sh` switches. |

### Switch the running VM (usual loop)

After a change to `configuration.nix`, or to `flake.nix`, apply it to the
running VM:

```bash
./bin/nixos-rebuild-remote.sh
```

The script copies `flake.nix`, `flake.lock` and `configuration.nix` to
`nixos:/tmp/multipass-nixos` and runs `nixos-rebuild switch` there with
`--flake /tmp/multipass-nixos#multipass-vm`. It uses `multipass exec`, not SSH,
because the Multipass daemon holds the SSH key. Uncommitted changes in the
working tree are picked up; no commit is needed.

`VM_NAME` (default `nixos`) and `REMOTE_DIR` (default `/tmp/multipass-nixos`)
override the targets. Only the three flake files are copied, so a new local
import must be added to `FLAKE_FILES` in the script and to `bin/build.sh`.

Verify a package landed without a full rebuild:

```bash
multipass exec nixos -- bash -lc 'command -v bat && bat --version'
```

The switch is local to the running VM. It does not update the QCOW2 image on
the host, so a fresh `bin/launch.sh` still boots the old configuration until
the image is rebuilt.

### Rebuild the image (after `flake.lock` or the base image changes)

Changes that affect the image itself (nixpkgs or Pi input updates, disk layout,
bootloader) need a new QCOW2, then a relaunch:

```bash
./bin/build.sh          # slow: QEMU uses software emulation, the builder has no /dev/kvm
./bin/launch.sh         # deletes the existing nixos VM, then launches the new image
```

`bin/build.sh` creates and installs Nix in the `builder` VM if missing, adds
the `kvm` Nix system feature, builds `.#qcow2`, and copies
`nixos-multipass.qcow2` into this directory (git-ignored). `bin/launch.sh`
defaults to 40G disk, 4G memory and 2 CPUs; the Multipass defaults are too
small and the build fails with "No space left on device" or an OOM kill.

Rebuilding the image discards the running VM. Ask before running
`bin/launch.sh`, and run `bin/build.sh` only when the change requires it.

### Update inputs

Run `nix flake update` (or `nix flake update pi`) inside the `builder` VM, copy
`flake.lock` back to the Mac, then rebuild the image.

## Log in

```bash
./bin/login.sh          # ssh to the nixos VM as ubuntu
multipass shell nixos   # fallback
```

## Version control

This is a Jujutsu (jj) repository, colocated with git
(`.jj/repo/store/git_target` points at `.git`). Use `jj`, not `git`: the
working copy is a commit, so there is nothing to stage. Commit messages follow Scoped Commits
(<https://scopedcommits.com/>) — `scope: imperative description`, for example
`nixos: add bat to system packages`. Bookmark `main` does not auto-advance;
move it before pushing.
