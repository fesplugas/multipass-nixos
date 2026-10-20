{ config, lib, pkgs, modulesPath, ... }:

{
  # The minimal profile disables documentation, fonts, default packages and
  # command-not-found. The headless profile removes the graphical console options.
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    "${modulesPath}/profiles/headless.nix"
  ];

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
      PrintLastLog = false;
      # Multipass retries the login every second until cloud-init installs its
      # key. The failed attempts would get the host banned for a long time.
      PerSourcePenalties = "no";
    };
  };

  # Like the Ubuntu cloud image, the user exists before the first boot.
  # The image has no SSH key. The Multipass daemon makes one key pair and puts
  # the public key in the cloud-init user-data (`ssh_authorized_keys`).
  # cloud-init writes it to ~ubuntu/.ssh/authorized_keys at the first boot.
  # The account has no password.
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
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

  environment.systemPackages = with pkgs; [
    # Multipass runs cloud-init commands over SSH, so the command must be in the PATH.
    cloud-init

    # Editors and version control
    gitMinimal
    jujutsu
    gh
    vim
    helix

    # AI coding agent (built from source with the overlay in flake.nix).
    # `pi update` cannot update a Nix installation; update the `pi` flake input
    # and rebuild the image instead.
    pi

    # Command line tools
    age
    fzf
    htop
    jq
    mise
    ripgrep

    # Build toolchain for gems with native extensions
    cmake
    gcc
    gnumake
    pkg-config

    # Process managers (overmind runs each process in a tmux session)
    hivemind
    overmind
    tmux

    # Clients for the services below
    redis
  ];

  # Redis listens on localhost only, port 6379. The unit is redis-default.service.
  services.redis.servers.default = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  # RabbitMQ listens on localhost only, AMQP on port 5672. The management UI
  # and API (port 15672) come from the management plugin.
  services.rabbitmq = {
    enable = true;
    listenAddress = "127.0.0.1";
    managementPlugin.enable = true;
  };

  # PostgreSQL listens on localhost only, port 5432. The `ubuntu` role is a
  # superuser and owns a database with the same name, so `psql` works without
  # arguments. Local connections use peer authentication over the Unix socket.
  services.postgresql = {
    enable = true;
    enableTCPIP = false;
    ensureDatabases = [ "ubuntu" ];
    ensureUsers = [
      {
        name = "ubuntu";
        ensureDBOwnership = true;
        ensureClauses.superuser = true;
      }
    ];
  };

  # Rails apps connect over TCP as `postgres` with the password `postgres`. The
  # step runs at each start, after the module created the databases and roles,
  # so it also works on a data directory that exists already (`initialScript`
  # runs only when the data directory is new). The VM is a development VM and
  # PostgreSQL accepts TCP connections from localhost only.
  systemd.services.postgresql.postStart = lib.mkAfter ''
    ${config.services.postgresql.finalPackage}/bin/psql --no-psqlrc --command "ALTER ROLE postgres WITH PASSWORD 'postgres'"
  '';

  # Docker with the Compose plugin (`docker compose`). The nixpkgs docker
  # package includes the plugin. The ubuntu user is in the `docker` group (see
  # `users.users.ubuntu`), which gives access to the daemon socket and is equal
  # to root access on the VM.
  virtualisation.docker.enable = true;

  # mise downloads precompiled binaries (ruby, node, ...). They expect the
  # FHS dynamic loader at /lib64, which NixOS does not have. nix-ld provides it.
  # Without nix-ld, mise compiles every tool from source on NixOS.
  programs.nix-ld.enable = true;
  # Libraries that gems load at runtime with dlopen (ruby-vips loads libvips.so.42
  # through FFI) must be here, because nix-ld searches only this list.
  programs.nix-ld.libraries = with pkgs; [ libyaml vips ];

  # The precompiled Ruby has Ubuntu paths in its build settings (MKDIR_P is
  # /bin/mkdir, INSTALL is /usr/bin/install, GREP is /usr/bin/grep). NixOS has
  # only /bin/sh and /usr/bin/env, so `make install` of every gem with a native
  # extension fails. envfs mounts /bin and /usr/bin and resolves each program
  # through the PATH of the caller.
  services.envfs.enable = true;

  # Gems with native extensions (bigdecimal, pg, psych, ...) compile on install.
  # NixOS has no /usr/include and no /usr/lib, so the compiler looks for headers
  # and libraries in the dev packages below through these variables.
  environment.variables =
    let
      libs = with pkgs; [ openssl zlib libyaml libffi libpq libssh2 ];
    in
    {
      # mise compiles tools on NixOS unless told otherwise. Use the precompiled
      # binaries.
      MISE_ALL_COMPILE = "false";
      MISE_RUBY_COMPILE = "false";

      C_INCLUDE_PATH = lib.makeSearchPathOutput "dev" "include" libs;
      LIBRARY_PATH = lib.makeLibraryPath libs;
      PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" libs;
    };

  # Installers for user tools link their command into ~/.local/bin only when
  # that directory is already in the PATH. NixOS does not add it by default.
  environment.localBinInPath = true;

  # Fish is the interactive shell. The login shell stays bash, because Multipass
  # runs its own commands over SSH with the login shell. Bash starts fish only
  # for interactive sessions (`bash -c` commands are not changed).
  programs.fish.enable = true;
  programs.fish.interactiveShellInit = ''
    set --global fish_greeting
    ${pkgs.mise}/bin/mise activate fish | source

    # Change to the root of the current jj or git repository.
    function grt
        # Try jj first (for jj workspaces)
        set --local repo_root (jj root 2>/dev/null)
        if test -n "$repo_root"
            cd $repo_root
            return 0
        end

        # Fall back to git
        set repo_root (git rev-parse --show-toplevel 2>/dev/null)
        if test -n "$repo_root"
            cd $repo_root
            return 0
        end

        echo "error: repo root could not be found"
        return 1
    end
  '';
  programs.bash.interactiveShellInit = ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';

  # Image size. Each option removes data from the system closure.
  # The flake registry and `nix.nixPath` pin the nixpkgs source in the closure
  # (about 200 MiB). `nix shell nixpkgs#...` then uses the online registry.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;
  nix.channel.enable = false;

  # The base image ships root channel directories. Nix warns about them when
  # channels are disabled, so systemd-tmpfiles removes them.
  systemd.tmpfiles.rules = [
    "R /root/.nix-defexpr/channels - - - - -"
    "R /nix/var/nix/profiles/per-user/root/channels - - - - -"
  ];
}
