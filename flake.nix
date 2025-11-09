{
  description = "comicslate.org";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      trusted-ssh-keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBxRBsFGa8OFbviYDGSAKLgfm/K2XUxvCo+31FW37yab artem"
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCW0Pq7WVNeIRJDgPi0ux3ajwhs/QEy5Ya8GG+STYMjApnfqkfG4OKh59BJHlsb354L5MpiV1YPIbW7ryw+ibuA= artem@corp-titan-nano-macbook"
      ];
    in
    {
      # nixos-rebuild build-vm --flake .#smith
      # QEMU_KERNEL_PARAMS=console=ttyS0 result/bin/run-nixos-vm -nographic; reset
      nixosConfigurations.smith = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          persistenceCommon = "/persistent";
        };

        modules = [
          nixpkgs.nixosModules.notDetected
          inputs.disko.nixosModules.disko

          inputs.impermanence.nixosModules.impermanence
          # inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          inputs.nixos-hardware.nixosModules.common-pc-ssd
          inputs.sops-nix.nixosModules.sops
          (
            {
              lib,
              persistenceCommon,
              modulesPath,
              pkgs,
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
              ];

              fileSystems.${persistenceCommon}.neededForBoot = true;
              environment.persistence.${persistenceCommon} = {
                # https://nixos.org/manual/nixos/stable/#sec-nixos-state
                directories = [
                  "/var/lib/nixos" # auto-generated UID and GID maps
                  "/var/lib/systemd" # timers, random seed, clock sync etc
                  # - /var/lib/samba (password database)
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
          )
        ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            sops # sops hosts/common/secrets/root-password.bin
          ];
        };
      }
    );
}
