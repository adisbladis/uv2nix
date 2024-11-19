{
  description = "Pytest flake using uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # This example shows testing with pytest using uv2nix.
  # You should first read and understand the hello-world example before this one.

  outputs =
    {
      nixpkgs,
      uv2nix,
      pyproject-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      # Python sets grouped per system
      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) stdenv;

          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python312;
          };

          # An overlay of build fixups & test additions.
          pyprojectOverrides = final: prev: {

            # testing is the name of our example package
            testing = prev.testing.overrideAttrs (old: {

              passthru = old.passthru // {
                # Put all tests in the passthru.tests attribute set.
                # Nixpkgs also uses the passthru.tests mechanism for ofborg test discovery.
                #
                # For usage with Flakes we will refer to the passthru.tests attributes to construct the flake checks attribute set.
                tests =
                  let
                    # Construct a virtual environment with only the test dependency-group enabled for testing.
                    virtualenv = final.mkVirtualEnv "testing-pytest-env" {
                      testing = [ "test" ];
                    };

                  in
                  (old.tests or { })
                  // {
                    pytest = stdenv.mkDerivation {
                      name = "${final.testing.name}-pytest";
                      inherit (final.testing) src;
                      nativeBuildInputs = [
                        virtualenv
                      ];
                      dontConfigure = true;

                      # Because this package is running tests, and not actually building the main package
                      # the build phase is running the tests.
                      #
                      # In this particular example we also output a HTML coverage report, which is used as the build output.
                      buildPhase = ''
                        runHook preBuild
                        pytest --cov tests --cov-report html
                        runHook postBuild
                      '';

                      # Install the HTML coverage report into the build output.
                      #
                      # If you wanted to install multiple test output formats such as TAP outputs
                      # you could make this derivation a multiple-output derivation.
                      #
                      # See https://nixos.org/manual/nixpkgs/stable/#chap-multiple-output for more information on multiple outputs.
                      installPhase = ''
                        runHook preInstall
                        mv htmlcov $out
                        runHook postInstall
                      '';
                    };

                  };
              };
            });
          };

        in
        baseSet.overrideScope (lib.composeExtensions overlay pyprojectOverrides)
      );

    in
    {
      # Construct flake checks from Python set
      checks = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};
        in
        {
          inherit (pythonSet.testing.passthru.tests) pytest;
        }
      );

      # Expose Python virtual environments as packages.
      packages = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};

          # Add metadata attributes to the virtual environment.
          # This is useful to inject meta and other attributes onto the virtual environment derivation.
          #
          # See
          # - https://nixos.org/manual/nixpkgs/unstable/#chap-passthru
          # - https://nixos.org/manual/nixpkgs/unstable/#chap-meta
          addMeta =
            drv:
            drv.overrideAttrs (old: {
              # Pass through tests from our package into the virtualenv so they can be discovered externally.
              passthru = lib.recursiveUpdate (old.passthru or { }) {
                inherit (pythonSet.testing.passthru) tests;
              };

              # Set meta.mainProgram for commands like `nix run`.
              # https://nixos.org/manual/nixpkgs/stable/#var-meta-mainProgram
              meta = (old.meta or { }) // {
                mainProgram = "hello";
              };
            });

        in
        {
          default = addMeta (pythonSet.mkVirtualEnv "testing-env" workspace.deps.default);
          full = addMeta (pythonSet.mkVirtualEnv "testing-env-full" workspace.deps.all);
        }
      );

      # Use an editable Python set for development.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          editablePythonSet = pythonSets.${system}.overrideScope editableOverlay;
          virtualenv = editablePythonSet.mkVirtualEnv "testing-dev-env" workspace.deps.all;
        in
        {
          default = pkgs.mkShell {
            packages = [
              virtualenv
              pkgs.uv
            ];
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
              export UV_NO_SYNC=1
            '';
          };
        }
      );
    };
}
