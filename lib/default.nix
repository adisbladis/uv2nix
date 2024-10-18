{ lib, pyproject-nix }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) fix;
in
fix (
  self:
  mapAttrs (_: path: import path ({ inherit lib pyproject-nix; } // self)) {
    lock1 = ./lock1.nix;
    workspace = ./workspace.nix;
    renderers = ./renderers.nix;
    build = ./build.nix;
  }
)
