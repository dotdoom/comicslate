{
  lib,
  persistenceCommon,
  modulesPath,
  pkgs,
  config,
  trusted-ssh-keys,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.systemd-boot.configurationLimit = 5;
  networking.hostName = "smith";
  networking.domain = "comicslate.org";

  services.qemuGuest.enable = true;
  # workaround because the console defaults to serial
  boot.kernelParams = [ "console=tty" ];
  # initialize the display early to get a complete log
  boot.initrd.kernelModules = [
    "virtio_gpu"
    "zfs"
  ];

  sops.secrets.root-password = {
    sopsFile = secrets/root-password.bin;
    format = "binary";
    neededForUsers = true;
  };
  users.users.root.hashedPasswordFile = config.sops.secrets.root-password.path;

  services.openssh = {
    enable = true;
    # TODO: enable firewall and add firewall rule here.
    hostKeys = [
      # Don't need RSA.
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  boot.zfs.devNodes = "/dev/disk/by-path";

  boot.loader.systemd-boot.enable = true;
  users.users.root.openssh.authorizedKeys.keys = trusted-ssh-keys;
  networking.hostId = "474ffba4";

  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  systemd.network.links."10-wan" = {
    matchConfig.MACAddress = "92:00:06:b5:fe:47";
    linkConfig.Name = "wan0";
  };
  systemd.network.networks."20-wan-static" = {
    matchConfig.Name = "wan0";
    networkConfig = {
      DHCP = "no";
      Address = [ "2a01:4f9:c010:dff6::2/64" ];
    };
    routes = [
      { Gateway = "fe80::1"; }
    ];
  };

  # VM limitations:
  # 1. IPv4 required for GitHub access (wtf lol?). You can remove
  #    this paid address once nixos-rebuild works remotely.
  # 2. disko-install is copying files into /nix (overlayfs on iso)
  #    first, running out of 2GB RAM.
  #
  # Installation:
  # 1. Mount NixOS ISO
  # 2. sudo passwd
  # 3. ssh-copy-id
  # 4. sudo passwd -l root
  # 5. rm -rf comicslate/{result,*.qcow2,.direnv}
  #    scp -r comicslate root@smith.comicslate.org
  # 6. nix --extra-experimental-features 'nix-command flakes' \
  #      run nixpkgs#disko -- \
  #        --yes-wipe-all-disks \
  #        --flake ~/comicslate#smith \
  #        --mode destroy,format,mount
  # 7. cd /mnt && nixos-install --flake ~/comicslate#smith
  # 8. reboot
  disko.devices = {
    disk = builtins.listToAttrs (
      lib.lists.imap1 (index: path: {
        name = "root";
        value = {
          device = path;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "fmask=0077"
                    "dmask=0077"
                    # Mounting /boot is only needed for bootloader updates,
                    # it's not important during boot.
                    "x-systemd.automount"
                  ];
                };
              };
              swap = {
                size = "8G";
                content = {
                  type = "swap";
                  discardPolicy = "once";
                  randomEncryption = true;
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
      }) [ "/dev/sda" ]
    );
    # See also modules/zfs.nix
    zpool = {
      rpool = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autoexpand = "off";
        };
        rootFsOptions = {
          mountpoint = "none";
          compression = "lz4";
          xattr = "sa";
          atime = "off";
          dedup = "off";
          acltype = "off";
          recordsize = "64k";
        };
        datasets = {
          nix = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };
          persistent = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = persistenceCommon;
          };
          reserved = {
            type = "zfs_fs";
            options.refreservation = "4G"; # ~10% assuming 40GB disk
          };
        };
      };
    };
    nodev = {
      # from https://github.com/nix-community/disko/issues/1089
      "/" = {
        device = "none";
        fsType = "tmpfs";
        mountpoint = "/";
        mountOptions = [
          "defaults"
          "size=3G"
          "mode=755" # only root can write to those files
        ];
      };
    };
  };

  environment.systemPackages = [
    pkgs.htop
    pkgs.chromium
    pkgs.cloudflared
  ];

  sops.secrets.cloudflare-tunnel-comicslate = {
    sopsFile = secrets/cloudflare-tunnel-comicslate.json.bin;
    format = "binary";
  };
  sops.secrets."cloudflare-tunnel-cert" = {
    sopsFile = secrets/cloudflare-tunnel-cert.pem;
    format = "binary";
  };
  services.httpd.enable = true;
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflare-tunnel-cert".path;
    tunnels = {
      "comicslate" = {
        credentialsFile = config.sops.secrets.cloudflare-tunnel-comicslate.path;
        ingress = {
          # Remember to create a proxied CNAME to "<tunnelid>.cfargotunnel.com".
          "web2.comicslate.org" = "http://localhost:80";
          "ssh.comicslate.org" = "ssh://localhost:22";
        };
        default = "http_status:404";
        # For QUIC:
        # sysctl -w net.core.rmem_max=7500000
        # sysctl -w net.core.wmem_max=7500000
      };
    };
  };

  # TODO: https://github.com/NixOS/nixpkgs/pull/448934
  systemd.services.cloudflared-tunnel-comicslate.environment.TUNNEL_EDGE_IP_VERSION = "6";

  services.openssh.settings.Macs = lib.mkAfter [
    # Current defaults:
    "hmac-sha2-512-etm@openssh.com"
    "hmac-sha2-256-etm@openssh.com"
    "umac-128-etm@openssh.com"
    # Added for cloudflare SSH browser rendering:
    "hmac-sha2-256"
  ];

  fileSystems.${persistenceCommon}.neededForBoot = true;
  environment.persistence.${persistenceCommon} = {
    # https://nixos.org/manual/nixos/stable/#sec-nixos-state
    directories = [
      "/var/lib/nixos" # auto-generated UID and GID maps
      "/var/lib/systemd" # timers, random seed, clock sync etc
    ];
    files = [
      "/etc/machine-id"
      "/etc/zfs/zpool.cache"
      "/etc/ssh/ssh_host_ed25519_key"
    ];
  };

  # Doesn't matter with impermanence, and better to know that on
  # each deploy rather than reboot.
  users.mutableUsers = false;

  system.stateVersion = "25.11";
}
