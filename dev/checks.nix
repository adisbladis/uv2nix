{
  pkgs,
  uv2nix,
  lib,
  pyproject-nix,
}:
let
  inherit (pkgs) runCommand;
  inherit (lib)
    mapAttrs'
    nameValuePair
    ;

  # Overrides for nixpkgs buildPythonPackage
  #
  # Just enough overrides to make tests pass.
  # This is not, and will not, become an overrides stdlib.

  # Build system overrides for pyproject.nix's build infra
  buildSystemOverrides = {
    arpeggio = {
      setuptools = [ ];
      pytest-runner = [ ];
    };
    attrs = {
      hatchling = [ ];
      hatch-vcs = [ ];
      hatch-fancy-pypi-readme = [ ];
    };
    tomli.flit-core = [ ];
    coverage.setuptools = [ ];
    blinker.setuptools = [ ];
    certifi.setuptools = [ ];
    charset-normalizer.setuptools = [ ];
    idna.flit-core = [ ];
    urllib3 = {
      hatchling = [ ];
      hatch-vcs = [ ];
    };
    pip = {
      setuptools = [ ];
      wheel = [ ];
    };
    packaging.flit-core = [ ];
    requests.setuptools = [ ];
    pysocks.setuptools = [ ];
    pytest-cov.setuptools = [ ];
  };

  # Assemble overlay from spec
  pyprojectOverrides =
    final: prev:
    let
      inherit (final) resolveBuildSystem;
      addBuildSystems =
        pkg: spec:
        pkg.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ resolveBuildSystem spec;
        });
    in
    lib.mapAttrs (name: spec: addBuildSystems prev.${name} spec) buildSystemOverrides;

  mkCheck' =
    sourcePreference:
    {
      root,
      interpreter ? pkgs.python312,
      spec ? { },
      check ? null,
      name ? throw "No name provided",
      environ ? { },
    }:
    let
      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };

      # Build Python environment based on builder implementation
      pythonEnv =
        let
          # Generate overlay
          overlay = ws.mkPyprojectOverlay { inherit sourcePreference environ; };

          # Construct package set
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = interpreter;
            }).overrideScope
              (lib.composeExtensions overlay pyprojectOverrides);

        in
        # Render venv
        pythonSet.pythonPkgsHostHost.mkVirtualEnv "test-venv" spec;

    in
    if check != null then
      runCommand "check-${name}-pref-${sourcePreference}"
        {
          nativeBuildInputs = [ pythonEnv ];
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
        spec = {
          trivial = [ ];
        };
      };

      virtual = mkCheck {
        root = ../lib/fixtures/virtual;
        spec = {
          virtual = [ ];
        };
      };

      workspace = mkCheck {
        root = ../lib/fixtures/workspace;
        spec = {
          workspace = [ ];
          workspace-package = [ ];
        };
      };

      workspace-flat = mkCheck {
        root = ../lib/fixtures/workspace-flat;
        spec = {
          pkg-a = [ ];
          pkg-b = [ ];
        };
      };

      # Note: Kitchen sink example can't be fully tested until
      kitchenSinkA = mkCheck {
        root = ../lib/fixtures/kitchen-sink/a;
        spec = {
          a = [ ];
        };
      };

      noDeps = mkCheck {
        root = ../lib/fixtures/no-deps;
        spec = {
          no-deps = [ ];
        };
      };

      dependencyGroups = mkCheck {
        root = ../lib/fixtures/dependency-groups;
        spec = {
          dependency-groups = [ "group-a" ];
        };
      };

      optionalDeps = mkCheck {
        root = ../lib/fixtures/optional-deps;
        spec = {
          optional-deps = [ ];
        };
      };

      withExtra = mkCheck {
        name = "with-extra";
        root = ../lib/fixtures/with-extra;
        spec = {
          with-extra = [ ];
        };
        # Check that socks extra is available
        check = ''
          python -c "import socks"
        '';
      };

      onlyWheels = mkCheck {
        root = ../lib/fixtures/only-wheels;
        spec = {
          hgtk = [ ];
        };
      };

      testMultiChoicePackageNoMarker = mkCheck {
        name = "multi-choice-no-marker";
        root = ../lib/fixtures/multi-choice-package;
        spec = {
          multi-choice-package = [ ];
        };
        # Check that arpeggio _isn't_ available
        check = ''
          ! python -c "import arpeggio"
        '';
      };

      testMultiChoicePackageWithMarker = mkCheck {
        name = "multi-choice-with-marker";
        root = ../lib/fixtures/multi-choice-package;
        spec = {
          multi-choice-package = [ ];
        };

        # Check that arpeggio _is_ available
        check = ''
          python -c "import arpeggio"
        '';
        environ = {
          platform_release = "5.10.65";
        };
      };

      # Nixpkgs buildPythonPackage explodes when bootstrap deps are overriden
      bootstrapProjectDep = mkCheck {
        root = ../lib/fixtures/bootstrap-project-dep;
        spec = {
          packaging = [ ];
        };
      };

      editable-workspace =
        let
          workspaceRoot = ../lib/fixtures/workspace;
          ws = uv2nix.workspace.loadWorkspace { inherit workspaceRoot; };

          interpreter = pkgs.python312;

          # Generate overlays
          overlay = ws.mkPyprojectOverlay {
            inherit sourcePreference;
            environ = { };
          };
          editableOverlay = ws.mkEditablePyprojectOverlay {
            root = "$NIX_BUILD_TOP";
          };

          # Base package set
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = interpreter;
          };

          # Override package set with our overlays
          pythonSet = baseSet.overrideScope (
            lib.composeManyExtensions [
              overlay
              pyprojectOverrides
              editableOverlay
            ]
          );

          pythonEnv = pythonSet.pythonPkgsHostHost.mkVirtualEnv "editable-venv" {
            workspace = [ ];
          };

        in
        pkgs.runCommand "editable-workspace-test"
          {
            nativeBuildInputs = [ pythonEnv ];
          }
          ''
            cp -r ${workspaceRoot}/* .
            chmod +w .*
            test "$(python -c 'import workspace_package; print(workspace_package.hello())')" = "Hello from workspace-package!"
            substituteInPlace ./packages/workspace-package/src/workspace_package/__init__.py --replace-fail workspace-package mutable-package
            test "$(python -c 'import workspace_package; print(workspace_package.hello())')" = "Hello from mutable-package!"
            touch $out
          '';

    };
in
# Generate test matrix:
# builder impl  -> sourcePreference
mkChecks "wheel" // mkChecks "sdist"
