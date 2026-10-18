# multipass-nixos

A Nix flake that builds a NixOS 26.05 QCOW2 image (aarch64) for Multipass.

## Files

- `flake.nix`: the flake. It exposes the image as `packages.aarch64-linux.qcow2`.
- `configuration.nix`: the NixOS configuration. It enables cloud-init, SSH, and flakes.

## Requirements

- Multipass on an Apple Silicon Mac.
- A Linux builder. Nix on macOS cannot build `aarch64-linux` images. These steps build the image inside a Multipass VM.

## Build

Create the builder VM and copy the project into it:

```fish
multipass launch --name builder --cpus 4 --memory 8G --disk 40G
multipass exec builder -- mkdir nixos
multipass transfer flake.nix configuration.nix builder:nixos/
```

Install Nix in the builder VM:

```fish
multipass exec builder -- sh -c 'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm'
```

Allow the `kvm` feature. The builder VM has no `/dev/kvm`, so QEMU uses software emulation. The build is slow, but it works.

```fish
multipass exec builder -- sudo sh -c 'echo "extra-system-features = kvm" >> /etc/nix/nix.custom.conf'
multipass exec builder -- sudo systemctl restart nix-daemon
```

Build the image:

```fish
multipass exec builder -- bash -lc 'cd nixos && nix build .#qcow2'
```

Copy the image to the Mac:

```fish
multipass transfer builder:nixos/result/nixos-multipass.qcow2 .
```

## Launch

```fish
multipass launch file://$PWD/nixos-multipass.qcow2 --name nixos
multipass shell nixos
```

Multipass uses cloud-init to create the user `ubuntu` and to install your SSH key.

## Update the image

Change the files, copy them to the builder VM again with `multipass transfer flake.nix configuration.nix builder:nixos/`, and run the build steps. To update nixpkgs, run `nix flake update` in the builder VM and copy `flake.lock` back to the Mac.

## Clean up

```fish
multipass delete --purge builder nixos
```

## License

MIT. See [LICENSE](LICENSE).
