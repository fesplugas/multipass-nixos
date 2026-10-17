{
  description = "NixOS QCOW2 image for Multipass (aarch64)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
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
        qcow2 = nixos.config.system.build.images.qemu-efi;
        qcow2-debug = self.nixosConfigurations.multipass-debug.config.system.build.images.qemu-efi;
        default = self.packages.${system}.qcow2;
      };
    };
}
