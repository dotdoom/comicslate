{
  description = "comicslate.org";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    phps.url = "github:fossar/nix-phps";
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
    {
      # nixos-rebuild build-vm --flake .#smith
      # QEMU_KERNEL_PARAMS=console=ttyS0 result/bin/run-nixos-vm -nographic; reset
      nixosConfigurations.smith = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          persistenceCommon = "/persistent";
          trusted-ssh-keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBxRBsFGa8OFbviYDGSAKLgfm/K2XUxvCo+31FW37yab artem"
            "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCW0Pq7WVNeIRJDgPi0ux3ajwhs/QEy5Ya8GG+STYMjApnfqkfG4OKh59BJHlsb354L5MpiV1YPIbW7ryw+ibuA= artem@corp-titan-nano-macbook"
          ];
          phps = inputs.phps.packages.x86_64-linux;
        };

        modules = [
          nixpkgs.nixosModules.notDetected
          inputs.disko.nixosModules.disko

          inputs.impermanence.nixosModules.impermanence
          # inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          inputs.nixos-hardware.nixosModules.common-pc-ssd
          inputs.sops-nix.nixosModules.sops
          hosts/smith/default.nix
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
            ssh-to-age
            age-plugin-yubikey
          ];
        };
      }
    );
}
