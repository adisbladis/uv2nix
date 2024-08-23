{
  pkgs,
  uv2nix,
  lib,
}:

let
  # Just enough overrides to make tests pass.
  # This is not, and will not, become an overrides stdlib.
  overrides = final: prev: {
    arpeggio = prev.arpeggio.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
    });
  };

  mkCheck =
    {
      root,
      interpreter ? pkgs.python312,
      packages ? [ ],
    }:
    let
      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };
      overlay = ws.mkOverlay { };
      python = interpreter.override {
        self = python;
        packageOverrides = lib.composeExtensions overlay overrides;
      };
    in
    python.withPackages (ps: map (name: ps.${name}) packages);

in

{
  trivial = mkCheck {
    root = ../lib/fixtures/trivial;
    packages = [ "trivial" ];
  };

  workspace = mkCheck {
    root = ../lib/fixtures/workspace;
    packages = [
      "workspace"
      "workspace-package"
    ];
  };

  workspace-flat = mkCheck {
    root = ../lib/fixtures/workspace-flat;
    packages = [
      "pkg-a"
      "pkg-b"
    ];
  };
}
