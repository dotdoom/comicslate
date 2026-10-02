{
  description = "comicslate.org";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    fw_nix = {
      url = "git+https://github.com/futureware-tech/nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.git-hooks.follows = "git-hooks";
    };
    phps.url = "github:fossar/nix-phps";
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
      systems,
      ...
    }@inputs:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      checks = eachSystem (system: {
        pre-commit-check = inputs.git-hooks.lib.${system}.run (
          {
            src = ./.;
          }
          // inputs.fw_nix.lib.pre-commit
        );
      });

      # nixos-rebuild build-vm --flake .#smith
      # QEMU_KERNEL_PARAMS=console=ttyS0 result/bin/run-nixos-vm -nographic; reset
      nixosConfigurations.smith = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          persistenceCommon = "/persistent";
          phps = inputs.phps.packages.x86_64-linux;
        };

        modules = [
          inputs.fw_nix.nixosModules.identities
          inputs.fw_nix.nixosModules.sshd
          inputs.fw_nix.nixosModules.systemd
          inputs.fw_nix.nixosModules.nix-settings
          inputs.fw_nix.nixosModules.nix-gc
          inputs.fw_nix.nixosModules.tools
          nixpkgs.nixosModules.notDetected
          inputs.disko.nixosModules.disko

          inputs.impermanence.nixosModules.impermanence
          # inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          inputs.nixos-hardware.nixosModules.common-pc-ssd
          inputs.sops-nix.nixosModules.sops
          hosts/smith/default.nix
        ];
      };

      devShells = eachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
        in
        {
          default = pkgs.mkShell {
            packages =
              enabledPackages
              ++ (with pkgs; [
                sops # sops hosts/common/secrets/root-password.bin
                ssh-to-age
                age-plugin-yubikey
                age-plugin-se
              ]);
            inherit shellHook;
          };
        }
      );
    };
}
