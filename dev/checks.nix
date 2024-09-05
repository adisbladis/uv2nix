{
  pkgs,
  uv2nix,
  lib,
}:
let
  inherit (pkgs) runCommand;
  inherit (lib) toList mapAttrs' nameValuePair;

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
      arpeggio = (addBuildSystem prev.arpeggio final.setuptools).overrideAttrs (old: {
        propagatedBuildInputs = old.propagatedBuildInputs ++ [ final.pytest-runner ];
      });
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
      pysocks = addBuildSystem prev.pysocks final.setuptools;
    };

  mkCheck' =
    sourcePreference:
    {
      root,
      interpreter ? pkgs.python312,
      packages ? [ ],
      testOverrides ? _: _: { },
      check ? null,
      name ? throw "No name provided",
      environ ? { },
    }:
    let
      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };
      overlay = ws.mkOverlay { inherit sourcePreference environ; };
      python = interpreter.override {
        self = python;
        packageOverrides = lib.composeManyExtensions [
          overlay
          overrides
          testOverrides
        ];
      };

      pythonEnv = python.withPackages packages;
    in
    if check != null then
      runCommand "check-${name}-pref-${sourcePreference}"
        {
          nativeBuildInputs = [ pythonEnv ];
          passthru = {
            inherit (python) pkgs;
            inherit python;
          };
        }
        ''
          ${check}
          touch $out
        ''
    else
      pythonEnv;

  mkChecks =
    sourcePreference:
    let
      mkCheck = mkCheck' sourcePreference;
    in
    mapAttrs' (name: v: nameValuePair "${name}-pref-${sourcePreference}" v) {
      trivial = mkCheck {
        root = ../lib/fixtures/trivial;
        packages = ps: [ ps."trivial" ];
      };

      virtual = mkCheck {
        root = ../lib/fixtures/virtual;
        packages = ps: [ ps."virtual" ];
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
        name = "with-extra";
        root = ../lib/fixtures/with-extra;
        packages = ps: [ ps."with-extra" ];
        # Check that socks extra is available
        check = ''
          python -c "import socks"
        '';
      };

      onlyWheels = mkCheck {
        root = ../lib/fixtures/only-wheels;
        packages = ps: [ ps."hgtk" ];
      };

      testMultiChoicePackageNoMarker = mkCheck {
        name = "multi-choice-no-marker";
        root = ../lib/fixtures/multi-choice-package;
        packages = ps: [ ps."multi-choice-package" ];
        # Check that arpeggio _isn't_ available
        check = ''
          ! python -c "import arpeggio"
        '';
        # Work around python-runtime-deps-check-hook bug where it can fail depending on uname
        testOverrides = _pyfinal: pyprev: {
          multi-choice-package = pyprev.multi-choice-package.overridePythonAttrs (_old: {
            dontCheckRuntimeDeps = true;
          });
        };
      };

      testMultiChoicePackageWithMarker = mkCheck {
        name = "multi-choice-with-marker";
        root = ../lib/fixtures/multi-choice-package;
        packages = ps: [ ps."multi-choice-package" ];
        # Check that arpeggio _is_ available
        check = ''
          python -c "import arpeggio"
        '';
        environ = {
          platform_release = "5.10.65";
        };
        # Work around python-runtime-deps-check-hook bug where it can fail depending on uname
        testOverrides = _pyfinal: pyprev: {
          multi-choice-package = pyprev.multi-choice-package.overridePythonAttrs (_old: {
            dontCheckRuntimeDeps = true;
          });
        };
      };
    };
in
# Generate test set twice: Once with wheel sourcePreference and once with sdist sourcePreference
mkChecks "wheel" // mkChecks "sdist"
