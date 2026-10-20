{
  description = "NixOS QCOW2 image for Multipass (aarch64)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The Pi coding agent builds from source through its official flake. The
    # flake pins its own nixpkgs, but the overlay below builds Pi with the
    # nixpkgs of this flake, so `follows` keeps one nixpkgs in the lock.
    pi.url = "github:earendil-works/pi/stable";
    pi.inputs.nixpkgs.follows = "nixpkgs";
    pi.inputs.nixpkgs-darwin-x64.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, pi }:
    let
      system = "aarch64-linux";
      nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Defines pkgs.pi (see the package list in configuration.nix).
          { nixpkgs.overlays = [ pi.overlays.default ]; }
          ./configuration.nix
        ];
      };
    in
    {
      nixosConfigurations.multipass = nixos;

      # The running system: the base configuration plus the module that the
      # `qemu-efi` image variant adds (disk layout and bootloader). Use it with
      # `nixos-rebuild switch --flake .#multipass-vm` (see bin/).
      nixosConfigurations.multipass-vm = nixos.extendModules {
        modules = [ "${nixpkgs}/nixos/modules/virtualisation/disk-image.nix" ];
      };

      # Debug variant: root logs in on the console without a password.
      # Never use it outside local tests.
      nixosConfigurations.multipass-debug = nixos.extendModules {
        modules = [
          {
            users.users.root.initialHashedPassword = "";
            services.getty.autologinUser = "root";
          }
        ];
      };

      packages.${system} = {
        # The `qemu-efi` image variant does not expose `additionalSpace` or the
        # compression, so call the image builder directly. The root partition
        # grows at the first boot, so the image needs only a small free space.
        qcow2 = import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit (nixpkgs) lib;
          inherit (self.nixosConfigurations.multipass-vm) config pkgs;
          baseName = "nixos-multipass";
          format = "qcow2-compressed";
          partitionTableType = "efi";
          diskSize = "auto";
          additionalSpace = "64M";
        };
        qcow2-debug = self.nixosConfigurations.multipass-debug.config.system.build.images.qemu-efi;
        default = self.packages.${system}.qcow2;
      };
    };
}
