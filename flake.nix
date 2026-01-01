{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    steam-fetcher = {
      url = "github:nix-community/steam-fetcher";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      steam-fetcher,
    }@inputs:

    let
      # Only x86_64-linux is supported
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          steam-fetcher.overlay
          self.overlays.default
        ];
        config.allowUnfree = true;
      };
    in

    {
      overlays = rec {
        default = scpsl-server;
        scpsl-server = final: prev: {
          inherit (self.packages.${final.stdenv.hostPlatform.system}) scpsl-server;
        };
      };

      nixosModules = rec {
        default = scpsl-server;
        scpsl-server = import ./modules/scpsl.nix { inherit self; };
      };

      packages.${system} = {
        scpsl-server = pkgs.callPackage ./pkgs/scpsl-server/package.nix { };
        generate-docs = pkgs.callPackage ./pkgs/generate-doc.nix { inherit inputs; };
      };

      checks.${system} = { inherit (self.packages.${system}) scpsl-server; };
    };
}
