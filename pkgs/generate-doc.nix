{
  lib,
  nixosOptionsDoc,
  inputs,
}:

let
  options =
    (lib.evalModules {
      modules = (import (inputs.nixpkgs + "/nixos/modules/module-list.nix")) ++ [
        { nixpkgs.hostPlatform = "x86_64-linux"; }
        inputs.self.nixosModules.default
      ];
    }).options.services.scpsl-server;
in

(nixosOptionsDoc { options.services.scpsl-server = options; }).optionsCommonMark
