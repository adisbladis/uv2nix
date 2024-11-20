{
  description = "Uv2nix overriding example";

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

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python312;
          };

          overlays = [
            pyproject-build-systems.overlays.default
            overlay
            # Note: Files are only split for documentation structuring purposes.
            # This is not considered a best practice.
            (import ./overrides-sdist.nix { inherit pkgs; })
            (import ./overrides-wheels.nix { inherit pkgs; })
          ];

        in
        baseSet.overrideScope (lib.composeManyExtensions overlays)
      );

    in
    {
      packages = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};
        in
        {
          default = pythonSet.mkVirtualEnv "overriding-env" workspace.deps.default;
        }
      );
    };
}
