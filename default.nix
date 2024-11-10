{ lib, pyproject-nix }:
{
  lib = import ./lib {
    inherit pyproject-nix;
    inherit lib;
  };
}
