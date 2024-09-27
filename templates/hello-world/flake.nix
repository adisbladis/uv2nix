{
  description = "Hello world flake using uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:adisbladis/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Disclaimer: Uv2nix is new and experimental.
  # Users are expected to be able to contribute fixes.
  #
  # Note that uv2nix is _not_ using Nixpkgs buildPythonPackage.
  # It's using https://nix-community.github.io/pyproject.nix/build.html

  outputs =
    {
      nixpkgs,
      uv2nix,
      pyproject-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Load a uv workspace from a workspace root.
      # Uv2nix treats all uv projects as workspace projects.
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      # Create package overlay from workspace.
      overlay = workspace.mkPyprojectOverlay {
        # Prefer prebuilt binary wheels as a package source.
        # Sdists are less likely to "just work" because of the metadata missing from uv.lock.
        # Binary wheels are more likely to, but may still require overrides for library dependencies.
        sourcePreference = "wheel"; # or sourcePreference = "sdist";
        # Optionally customise PEP 508 environment
        # environ = {
        #   platform_release = "5.10.65";
        # };
      };

      # Extend generated overlay with build fixups
      #
      # Uv2nix can only work with what it has, and uv.lock is missing essential metadata to perform some builds.
      # This is an additional overlay implementing build fixups.
      # See:
      # - https://adisbladis.github.io/uv2nix/FAQ.html
      pyprojectOverrides =
        let
          # Implement build fixups here.
          #
          # In this example the same overlay is used for both build-system & final dependencies,
          # but you can use different overrides if you want to.
          overlay' = _final: _prev: {
            # Implement build fixups here.
          };
        in
        _final: prev: {
          # Override build platform dependencies
          #
          # Use this when overriding build-systems that need to run on the build platform.
          pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope overlay';

          # Override target platform packages.
          #
          # Use this to override packages for the target platform.
          pythonPkgsHostHost = prev.pythonPkgsHostHost.overrideScope overlay';
        };

      # This example is only using x86_64-linux
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Use Python 3.12 from nixpkgs
      python = pkgs.python312;

      # Construct package set
      pythonSet =
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (lib.composeExtensions overlay pyprojectOverrides);

    in
    {
      # Package a virtual environment as our main application.
      packages.x86_64-linux.default = pythonSet.pythonPkgsHostHost.mkVirtualEnv "hello-world-env" {
        hello-world = [ ];
      };

      # This example provides two different modes of development:
      # - Impurely using uv to manage virtual environments
      # - Pure development using uv2nix to manage virtual environments
      devShells.x86_64-linux = {
        # It is of course perfectly OK to keep using an impure virtualenv workflow and only use uv2nix to build packages.
        # This devShell simply adds Python and undoes the dependency leakage done by Nixpkgs Python infrastructure.
        impure = pkgs.mkShell {
          packages = [
            python
            pkgs.uv
          ];
          shellHook = ''
            unset PYTHONPATH
          '';
        };

        # This devShell uses uv2nix to construct a virtual environment purely from Nix, using the same dependency specification as the application.
        # The notable difference is that we also apply another overlay here enabling editable mode ( https://setuptools.pypa.io/en/latest/userguide/development_mode.html ).
        #
        # This means that any changes done to your local files do not require a rebuild.
        uv2nix =
          let
            # Create an overlay enabling editable mode for all local dependencies.
            editableOverlay = workspace.mkEditablePyprojectOverlay {
              # Use environment variable
              root = "$REPO_ROOT";
              # Optional: Only enable editable for these packages
              # members = [ "hello-world" ];
            };

            # Override previous set with our overrideable overlay.
            pythonSet' = pythonSet.overrideScope editableOverlay;

            # Build virtual environment
            virtualenv = pythonSet'.pythonPkgsHostHost.mkVirtualEnv "hello-world-dev-env" {
              # Add hello world with it's dev dependencies
              hello-world = [ "dev-dependencies" ];
            };

          in
          pkgs.mkShell {
            packages = [
              virtualenv
              pkgs.uv
            ];
            shellHook = ''
              # Undo dependency propagation by nixpkgs.
              unset PYTHONPATH
              # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };
      };
    };
}
