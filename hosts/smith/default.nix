{
  lib,
  persistenceCommon,
  modulesPath,
  pkgs,
  config,
  trusted-ssh-keys,
  phps,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub.configurationLimit = 5;

  networking.hostName = "smith";
  networking.domain = "comicslate.org";

  networking.firewall.enable = true;
  networking.nftables.enable = true;

  services.qemuGuest.enable = true;
  # workaround because the console defaults to serial
  boot.kernelParams = [ "console=tty" ];
  # initialize the display early to get a complete log
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  sops.secrets.root-password = {
    sopsFile = secrets/root-password.bin;
    format = "binary";
    neededForUsers = true;
  };
  users.users.root.hashedPasswordFile = config.sops.secrets.root-password.path;

  services.openssh = {
    enable = true;
    openFirewall = true;
    hostKeys = [
      # Don't need RSA.
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = trusted-ssh-keys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYCsprpT+Q8L4X4hXUjF3/0P1ACYvPuP+WQSjyllxeQ root@nas"
  ];
  networking.hostId = "474ffba4";

  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  systemd.network.networks."20-ether-static" = {
    matchConfig.Name = "en*"; # only physical interfaces - avoid managing veth.
    networkConfig = {
      # - fetch GitHub (nixpkgs)
      # - fetch ghcr.io (RSS bot)
      # - fetch RSS feeds (RSS bot)
      # - connect to Discord (RSS bot)
      DHCP = "ipv4";
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
  #    first, running out of 2GB RAM, so we use nixos-install directly.
  #
  # Installation:
  # 1. Mount NixOS ISO
  # 2. sudo passwd
  # 3. ip addr add pref::2/64 dev enp1s0 &&
  #    ip ro add default via fe80::1 dev enp1s0
  # 4. ssh-copy-id
  # 5. sudo passwd -l root
  # 6. rm -rf comicslate/{result,*.qcow2,.direnv}
  #    scp -r comicslate root@smith.comicslate.org
  # 7. nix --extra-experimental-features 'nix-command flakes' \
  #      run nixpkgs#disko -- \
  #        --yes-wipe-all-disks \
  #        --flake ~/comicslate#smith \
  #        --mode destroy,format,mount
  # 8. cd /mnt && nixos-install --flake ~/comicslate#smith
  # 9. reboot
  disko.devices = {
    disk = {
      root = {
        device = "/dev/sda";
        type = "disk";
        content = {
          # x86 Hetzner VMs only support legacy (non-EFI) boot.
          # Assuming 20GB+ disk.
          # ZFS doesn't make sense in single-disk, RAM-constrained VM env.
          type = "gpt";
          partitions = {
            boot = {
              size = "8M";
              type = "EF02"; # for grub MBR
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                discardPolicy = "once";
              };
            };
            persistence = {
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persistent";
                mountOptions = [ "noatime" ];
              };
            };
            nix = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
                mountOptions = [ "noatime" ];
              };
            };
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
          "size=2G" # out of 4GB RAM
          "mode=755" # only root can write to those files
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    cloudflared
    tcpdump
    ncdu
    vim
  ];

  programs.htop = {
    enable = true;
    settings = {
      # Header
      header_margin = false;
      detailed_cpu_time = true;
      show_cpu_frequency = true;
      show_cpu_temperature = true;
      column_meters_0 = "CPU Memory Swap DiskIO";
      column_meter_modes_0 = "1 1 1 2";
      column_meters_1 = "Tasks LoadAverage Uptime NetworkIO";
      column_meter_modes_1 = "2 2 2 2";

      # Tabs
      "screen:1_Main" =
        "PID USER PRIORITY NICE M_VIRT M_RESIDENT M_SHARE STATE PERCENT_CPU PERCENT_MEM TIME Command";
      "screen:2_IO" =
        "PID USER IO_PRIORITY IO_RATE IO_READ_RATE IO_WRITE_RATE PERCENT_SWAP_DELAY PERCENT_IO_DELAY Command";

      # List
      hide_kernel_threads = true;
      hide_userland_threads = true;
      highlight_base_name = true;
      tree_view = true;
    };
  };

  sops.secrets.cloudflare-tunnel-comicslate = {
    # This is the file generated by "cloudflared tunnel create comicslate".
    sopsFile = secrets/cloudflare-tunnel-comicslate.json.bin;
    format = "binary";
  };
  sops.secrets."cloudflare-tunnel-cert" = {
    # This is the cert.pem obtained from "cloudflared tunnel login". It is
    # required to declaratively set up the tunnel (below), and it does have
    # write access to tunnels API.
    sopsFile = secrets/cloudflare-tunnel-cert.pem;
    # Place the file for "cloudflared" tool to find, if needed to be used from
    # command line (e.g. "cloudflared tunnel list").
    path = "/root/.cloudflared/cert.pem";
    format = "binary";
  };

  fileSystems."/var/www" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_103973620";
    fsType = "ext4";
    options = [
      "nofail"
      "noatime"
    ];
  };

  nixpkgs.config.allowUnfree = true; # for google-chrome
  systemd.services.comicsbot = {
    description = "comics renderer";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      nodejs_20
      git
      bash
      coreutils
    ];

    serviceConfig = {
      User = "wwwrun";
      # Group = "wwwrun";
      WorkingDirectory = "/var/www/.htsecure/comicsbot";

      # Restart automatically if it crashes
      Restart = "always";
      RestartSec = "10s";

      # Basic hardening (Optional but recommended)
      ProtectSystem = "full";
      PrivateTmp = true;
    };

    environment = {
      CHROME_EXECUTABLE_PATH = lib.getExe pkgs.google-chrome;
    };

    preStart = ''
      if [ ! -d .git ]; then
        echo "Initializing git..."
        git init
        git remote add origin https://github.com/dotdoom/comicsbot || true
      fi

      echo "Updating sources..."
      git fetch origin
      git pull --rebase origin master || echo "Git pull failed, attempting to continue..."

      if [ ! -f config/config.json ]; then
        echo "Config not found, creating from example..."
        mkdir -p config
        if [ -f config/config.example.json ]; then
          cp config/config.example.json config/config.json
        fi
      fi

      echo "Installing dependencies..."
      # We set the cache to a local folder to avoid permission issues
      export npm_config_cache="$PWD/.npm"
      npm ci --loglevel info --no-audit --no-save
    '';

    script = ''
      npm start
    '';
  };

  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflare-tunnel-cert".path;
    tunnels = {
      "comicslate" = {
        credentialsFile = config.sops.secrets.cloudflare-tunnel-comicslate.path;
        ingress = {
          # Remember to create a proxied CNAME to "<tunnelid>.cfargotunnel.com",
          # e.g. automatically using
          # $ cloudflared tunnel route dns <tunnel-name> <dns-record>
          # i.e.
          # $ cloudflared tunnel route dns comicslate web2.comicslate.org
          "comicslate.org" = "http://localhost:80";
          "admin.comicslate.org" = "http://localhost:80";
          "test.comicslate.org" = "http://localhost:80";
          "app.comicslate.org" = "http://localhost:80";
          "osp.dget.cc" = "http://localhost:80";

          # Create an Application for browser based access without installing
          # "cloudflared" on the client.
          "smith-ssh.comicslate.org" = "ssh://localhost:22";
          # TODO: smith.comicslate.org, and use IP address for emergency
          # reachability only.
          # This is not working at all, neither web nor command line. Why?
          # Check out https://developers.cloudflare.com/cloudflare-one/tutorials/gitlab/
        };
        default = "http_status:404";
        # TODO for QUIC:
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
  services.openssh.extraConfig = ''
    Match Address 127.0.0.1
      # Enable password authentication over cloudflared tunnel, which is already
      # secured by Cloudflare login.
      PasswordAuthentication yes
  '';

  sops.secrets.nullmailer-remotes = {
    sopsFile = secrets/nullmailer-remotes.bin;
    format = "binary";
    owner = "nullmailer";
  };
  services.nullmailer = {
    enable = true;
    config = {
      adminaddr = "dot.doom@gmail.com";
      defaulthost = "comicslate.org";
    };
    remotesFile = config.sops.secrets.nullmailer-remotes.path;
  };

  sops.secrets.discord-bot = {
    sopsFile = secrets/discord-bot.env;
    format = "dotenv";
  };
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.containers = {
    monitorss = {
      image = "docker.io/synzen/monitorss:latest";
      volumes = [
        "/var/www/.htsecure/Discord.RSS:/data"
      ];
      environmentFiles = [ config.sops.secrets.discord-bot.path ];
      environment = {
        DRSS_DATABASE_URI = "/data";
      };
    };
  };

  fileSystems.${persistenceCommon}.neededForBoot = true;
  environment.persistence.${persistenceCommon} = {
    # https://nixos.org/manual/nixos/stable/#sec-nixos-state
    directories = [
      "/var/lib/nixos" # auto-generated UID and GID maps
      "/var/lib/systemd" # timers, random seed, clock sync etc
      "/var/lib/containers" # podman: rss bot
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
    ];
  };

  /*
    fonts = {
      fontDir.enable = true;
      packages = with pkgs; [
        carlito # Chrome OS equivalent to Calibri
        caladea # Chrome OS equivalent to Cambria
        google-fonts
      ];

      fontconfig = {
        enable = true;
        localConf = ''
          <!-- Enable subpixel rendering -->
          <match target="font">
            <edit mode="assign" name="rgba" ><const>rgb</const></edit>
          </match>
          <!-- Subpixel rendering doesn't work with hinting -->
          <match target="font">
            <edit mode="assign" name="hinting"><bool>false</bool></edit>
          </match>

          <match target="font">
            <edit mode="assign" name="antialias"><bool>true</bool></edit>
          </match>

          <match target="font">
            <edit mode="assign" name="lcdfilter"><const>lcddefault</const></edit>
          </match>
        '';

        defaultFonts = {
          sansSerif = [
            "Arimo"
            "Carlito"
            "Liberation Sans"
            "DejaVu Sans"
          ];
          serif = [
            "Tinos"
            "Caladea"
            "Liberation Serif"
            "DejaVu Serif"
          ];
          monospace = [
            "Cousine"
            "Liberation Mono"
            "DejaVu Sans Mono"
          ];
        };
      };
    };
  */

  sops.secrets.webdav-password = {
    sopsFile = secrets/webdav-password.bin;
    format = "binary";
    owner = "wwwrun";
  };

  services.logrotate.settings = {
    "/var/www/.htsecure/log/*.log" = {
      daily = true;
      minsize = "5M";
      missingok = true;
      rotate = 9;
      compress = true;
      delaycompress = true;
      notifempty = true;
      nocreate = true;
      sharedscripts = true;

      postrotate = ''
        ${pkgs.systemd}/bin/systemctl reload httpd.service
      '';
    };
  };

  services.journald.storage = "volatile";

  systemd.tmpfiles.rules = [
    "d /run/httpd 0700 wwwrun wwwrun -"
  ];

  services.httpd = {
    enable = true;

    # we configure our own logging below
    logFormat = "none";
    logPerVirtualHost = false;

    enablePHP = true;
    phpPackage = phps.php74;
    phpOptions = ''
      ; Doku relies on filesystem lookup a lot, this cache is handy.
      realpath_cache_size = 40M
      ; There's also a limit in CloudFlare, up to 100MB on free plan.
      upload_max_filesize = 15M
      post_max_size = 15M
      ; Some processes can grow really large.
      memory_limit = 1G
      ; sendmail command line working with nullmailer
      sendmail_path = ${config.security.wrapperDir}/sendmail -t -i
    '';
    extraModules = [
      # For "AddOutputFilterByType DEFLATE":
      "filter"
      "deflate"
      # cloudflared tunnel de-ip
      "remoteip"
      # WebDav access
      "dav"
      "dav_fs"
    ];
    extraConfig = ''
      # cloudflared tunnel de-ip
      RemoteIPHeader CF-Connecting-IP
      RemoteIPInternalProxy 127.0.0.1 ::1

      DAVLockDB /run/httpd/davlockdb
    '';
    virtualHosts =
      let
        log = host: ''
          ErrorLog /var/www/.htsecure/log/${host}.error.log
          # Stop logging "AH01630: client denied by server configuration".
          LogLevel warn authz_core:crit
          # Add "rewrite:trace3" to the line above for RewriteEngine debug.
          CustomLog /var/www/.htsecure/log/${host}.access.log combined

          CustomLog /var/www/.htsecure/log/${host}.full.log \
            "[%{%F %T}t.%{usec_frac}t %{%z}t]\n\
            Client: %a (%{CF-IPCountry}i)\n\
            Request: %{X-Forwarded-Proto}i://%{Host}i %r\n\
            User-Agent: %{User-Agent}i\n\
            Referer: %{Referer}i\n\
            Server: [%A:%{local}p] %v: %R:%f\n\
            Response: HTTP %s %301,302{Location}o, %B bytes of %{Content-Type}o (%{Content-Encoding}o) in %D usec"
        '';

        safety = ''
          # https://googlechrome.github.io/samples/csp-upgrade-insecure-requests/
          # If there are insecure (http://) links on the page, they will automatically
          # be replaced with https, without showing the "mixed content" warning.
          #2016-04-06: DISABLED: there are unfortunately http-only links on the pages.
          #Header set "Content-Security-Policy" "upgrade-insecure-requests"

          Header set "X-Frame-Options" "SAMEORIGIN"
        '';

        local = [
          {
            ip = "127.0.0.1";
            port = 80;
          }
          {
            ip = "::1";
            port = 80;
          }
        ];
      in
      {
        "comicslate.org" = {
          listen = local;
          documentRoot = "/var/www/comicslate.org";
          serverAliases = [
            # localhost doesn't have HTTPS certificate, but Chrome is precompiled
            # with hardcoded list of HSTS which includes comicslate.org, forcing
            # the browser to try HTTPS regardless of options and flags.
            #
            # We use a fake hostname in our renderer to avoid hitting HSTS list.
            "render"
          ];
          extraConfig = ''
            ${log "comicslate.org"}
            ${safety}

            <Directory /var/www/comicslate.org>
              Options FollowSymLinks MultiViews
              AllowOverride All
            </Directory>
          '';
        };
        "test.comicslate.org" = {
          listen = local;
          documentRoot = "/var/www/test.comicslate.org";
          extraConfig = ''
            ${log "test.comicslate.org"}
            ${safety}

            <Directory /var/www/test.comicslate.org>
              Options FollowSymLinks MultiViews
              AllowOverride All
            </Directory>
          '';
        };
        "admin.comicslate.org" = {
          listen = local;
          documentRoot = "/var/www";
          extraConfig = ''
            ${log "admin.comicslate.org"}
            <Directory /var/www>
              Dav On
              AllowOverride None
              DirectoryIndex disabled

              AuthType Basic
              AuthName "Hoppla"
              AuthUserFile ${config.sops.secrets.webdav-password.path}
              Require valid-user

              <FilesMatch "^\.ht">
                Require valid-user
              </FilesMatch>
            </Directory>
          '';
        };
        "app.comicslate.org" = {
          listen = local;
          extraConfig = ''
            ${log "app.comicslate.org"}
            AddOutputFilterByType DEFLATE application/json text/plain
            ProxyPreserveHost On
            ProxyPass "/" "http://localhost:8081/"
          '';
        };
        "osp.dget.cc" = {
          listen = local;
          documentRoot = "/var/www/osp.dget.cc";
          extraConfig = log "osp.dget.cc";
        };
      };
  };

  systemd.services.archives = {
    description = "Backup and rotation of comicslate archives";
    startAt = "daily";
    path = [ pkgs.p7zip ];
    serviceConfig = {
      User = "wwwrun";
      Type = "oneshot";
    };

    script = ''
      set -eu

      ARCHIVES_ROOT="/var/www/.htsecure/archives"
      TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

      mkdir -p "$ARCHIVES_ROOT"

      7zr a "$ARCHIVES_ROOT/pages_$TIMESTAMP.7z" \
          /var/www/comicslate.org/data/pages

      7zr a "$ARCHIVES_ROOT/meta_$TIMESTAMP.7z" \
          /var/www/comicslate.org/data/meta

      find "$ARCHIVES_ROOT" -type f -name '*.7z' -mtime +30 -delete
    '';
  };

  systemd.services.cleanup = {
    description = "Cleanup unused and stale files";
    startAt = "daily";
    path = [
      pkgs.findutils
      pkgs.gawk
      pkgs.coreutils-full
    ];

    serviceConfig = {
      User = "wwwrun";
      Type = "oneshot";
    };

    script = ''
      set -eu

      echo "Removing old rendered versions..."
      find /var/www/comicslate.org/data/media/u \
        -type f \
        -name "*@*.webp" \
        -print0 | \
      gawk -v RS='\0' '
        match($0, /^(.*)@([0-9]+)[.]webp$/, parts) {
          prefix = parts[1]         # The prefix, e.g., /var/www/data/u/sci-fi/freefall/1234
          timestamp = parts[2] + 0  # The timestamp, converted to a number

          if (prefix in newest_ts) {
            if (timestamp > newest_ts[prefix]) {
              printf "%s\0", newest_file[prefix]
              newest_ts[prefix] = timestamp
              newest_file[prefix] = $0
            } else {
              printf "%s\0", $0
            }
          } else {
            newest_ts[prefix] = timestamp
            newest_file[prefix] = $0
          }
        }' | xargs -0 rm -v

        echo "Removing stale cache files..."
        find /var/www/comicslate.org/data/cache \
          -type f \
          -mtime +90 \
          -print \
          -delete

        df -h /var/www
    '';
  };

  # Doesn't matter with impermanence, and better to know that on
  # each deploy rather than reboot.
  users.mutableUsers = false;

  system.stateVersion = "25.11";
}
