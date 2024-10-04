{
  description = "Immich SD Card Sync Service";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # Expose the NixOS module in the flake output
    nixosModules.immichSdCardSync = { config, lib, ... }: import ./immich-sd-card-sync.nix { inherit lib pkgs config; };

    # Add a formatter using nixpkgs-fmt
    formatter = pkgs.nixpkgs-fmt;
  };
}
