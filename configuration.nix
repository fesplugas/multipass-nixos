{ lib, pkgs, ... }:

{
  system.stateVersion = "26.05";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  # The Multipass QEMU driver attaches the disk as virtio-scsi, not virtio-blk.
  # The initrd needs these modules to find the root device.
  boot.initrd.availableKernelModules = [ "virtio_scsi" "sd_mod" "virtio_pci" "virtio_blk" ];

  # The qemu-efi image variant sets the disk layout, the bootloader, and the
  # root partition growth. Only the file name is set here.
  image.modules.qemu-efi.image.baseName = lib.mkForce "nixos-multipass";

  # Multipass passes the user, SSH keys and hostname through cloud-init.
  services.cloud-init = {
    enable = true;
    network.enable = true;
    # The NixOS module defaults to `users = [ "root" ]`. The default user
    # (`ubuntu`, below) is created only when the list has "default".
    settings.users = [ "default" ];
    settings.disable_root = true;
    # sshd creates the host keys. cloud-init must not delete and replace them.
    settings.ssh_deletekeys = false;

    # The NixOS module sets `system_info` with mkDefault. Any definition here
    # replaces the whole default, so `distro` and `network` are set again.
    settings.system_info = {
      distro = "nixos";
      network.renderers = [ "networkd" ];
      default_user = {
        name = "ubuntu";
        groups = [ "wheel" ];
        sudo = [ "ALL=(ALL) NOPASSWD:ALL" ];
        shell = "/run/current-system/sw/bin/bash";
      };
    };
  };

  # The NixOS kernel has no Joliet support (CONFIG_JOLIET is not set). The
  # Multipass cloud-init ISO has only Joliet file names, so the kernel shows
  # them as `meta_dat` and `user_dat`, and cloud-init rejects the ISO as an
  # invalid seed. libarchive reads Joliet in user space. Copy the files to the
  # NoCloud seed directory before cloud-init looks for a data source.
  systemd.services.multipass-seed = {
    description = "Copy the Multipass cloud-init ISO to the NoCloud seed directory";
    wantedBy = [ "cloud-init-local.service" ];
    before = [ "cloud-init-local.service" ];
    after = [ "systemd-udevd.service" ];
    path = [ pkgs.libarchive pkgs.systemd pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      udevadm settle --timeout=10
      device=/dev/disk/by-label/cidata
      [ -b "$device" ] || exit 0
      mkdir --parents /var/lib/cloud/seed/nocloud
      bsdtar --extract --file "$device" --directory /var/lib/cloud/seed/nocloud
    '';
  };

  # The NixOS module starts sshd only after cloud-init finishes, and cloud-init
  # has no timeout. Remove that ordering so sshd is always available. Multipass
  # retries the login until cloud-init has installed its key.
  systemd.services.cloud-init.before = lib.mkForce [ ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      # Multipass retries the login every second until cloud-init installs its
      # key. The failed attempts would get the host banned for a long time.
      PerSourcePenalties = "no";
    };
  };

  # Like the Ubuntu cloud image, the user exists before the first boot.
  # cloud-init only adds the key that Multipass sends. The account has no password.
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyd8VtyBf4AMGVUhYCslTs7z/H1XO675dzYhCJFsp2j fesplugas"
      # Public key of the local Multipass installation. `multipass shell` uses it.
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMTjfQGD+CHZK/iJ3aIf7ce4d5MPubvIKI7084oKlrqxYbvAbf2NeOmBAW9Qi/Xi0CcglECXHwbNF5lWX6Qyboq0SklzOZQ2nkbk4ehEWJBKPAAFnUeplYZPJHJWqTslEN06sJxXRwn21FZ82n/DNu2wuysB27A4D2q692Xknzw0JMdhzv6LzVXq/nHA09/K0T803FM36pPG3zgJS4FC0M1+hqhQFlzI4TEdkOk1yF3q0WIYCsUdtbYSGZvTw6gFqVfQIE1EG0p/kZxe4a9ZdwnSVEJ8RzoNpO1FOsi2mUBW8zN/6VOFz1MV3c6/PTExoCQLtlGnzvh8cAkVpAFsr/ ubuntu@localhost"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # cloud-init network support enables systemd-networkd. One network manager
  # must manage the interfaces, so use networkd for DHCP as well.
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # Multipass finds the VM by MAC address and keeps the first IP it sees. The
  # cloud-init network config identifies the DHCP client by MAC. Do the same
  # before cloud-init runs, so the VM keeps one IP address for the whole boot.
  systemd.network.networks."05-dhcp" = {
    matchConfig.Type = "ether";
    networkConfig.DHCP = "ipv4";
    dhcpV4Config.ClientIdentifier = "mac";
  };
  networking.hostName = "";

  services.qemuGuest.enable = true;

  # Multipass runs cloud-init commands over SSH, so the command must be in the PATH.
  environment.systemPackages = with pkgs; [ gitMinimal curl cloud-init htop jujutsu mise ];

  # Image size. Each option removes data from the system closure.
  # The flake registry and `nix.nixPath` pin the nixpkgs source in the closure
  # (about 200 MiB). `nix shell nixpkgs#...` then uses the online registry.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;
  nix.channel.enable = false;
  documentation.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  environment.defaultPackages = lib.mkForce [ ];
  programs.command-not-found.enable = false;
  fonts.fontconfig.enable = false;
}
