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
