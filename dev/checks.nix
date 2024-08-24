{
  pkgs,
  uv2nix,
  lib,
}:

let
  inherit (lib) toList;

  # Just enough overrides to make tests pass.
  # This is not, and will not, become an overrides stdlib.
  overrides =
    final: prev:
    let
      addBuildSystem =
        pkg: build-system:
        pkg.overridePythonAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ (toList build-system);
        });
    in
    {
      arpeggio = addBuildSystem prev.arpeggio final.setuptools;
      attrs = addBuildSystem prev.attrs [
        final.hatchling
        final.hatch-vcs
        final.hatch-fancy-pypi-readme
      ];
      blinker = addBuildSystem prev.blinker final.setuptools;
      certifi = addBuildSystem prev.certifi final.setuptools;
      charset-normalizer = addBuildSystem prev.charset-normalizer final.setuptools;
      idna = addBuildSystem prev.idna final.flit-core;
      urllib3 = addBuildSystem prev.urllib3 final.hatchling;
      pip = addBuildSystem prev.pip final.setuptools;
      requests = addBuildSystem prev.requests final.setuptools;
    };

  mkCheck =
    {
      root,
      interpreter ? pkgs.python312,
      packages ? [ ],
      testOverrides ? _: _: { },
    }:
    let
      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };
      overlay = ws.mkOverlay { };
      python = interpreter.override {
        self = python;
        packageOverrides = lib.composeManyExtensions [
          overlay
          overrides
          testOverrides
        ];
      };
    in
    python.withPackages packages;

in

{
  trivial = mkCheck {
    root = ../lib/fixtures/trivial;
    packages = ps: [ ps."trivial" ];
  };

  workspace = mkCheck {
    root = ../lib/fixtures/workspace;
    packages = ps: [
      ps."workspace"
      ps."workspace-package"
    ];
  };

  workspace-flat = mkCheck {
    root = ../lib/fixtures/workspace-flat;
    packages = ps: [
      ps."pkg-a"
      ps."pkg-b"
    ];
  };

  # Note: Kitchen sink example can't be fully tested until
  kitchenSinkA = mkCheck {
    root = ../lib/fixtures/kitchen-sink/a;
    packages = ps: [ ps.a ];
  };

  noDeps = mkCheck {
    root = ../lib/fixtures/no-deps;
    packages = ps: [ ps."no-deps" ];
  };

  optionalDeps = mkCheck {
    root = ../lib/fixtures/optional-deps;
    packages = ps: [ ps."optional-deps" ];
  };

  withExtra = mkCheck {
    root = ../lib/fixtures/with-extra;
    packages = ps: [ ps."with-build-requires" ];
  };
}
