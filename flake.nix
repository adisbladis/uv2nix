{
  description = "Uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixdoc.url = "github:nix-community/nixdoc";
    nixdoc.inputs.nixpkgs.follows = "nixpkgs";

    pyproject-nix.url = "github:nix-community/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-nix.inputs.nix-github-actions.follows = "nix-github-actions";
    pyproject-nix.inputs.mdbook-nixdoc.follows = "mdbook-nixdoc";
    pyproject-nix.inputs.treefmt-nix.follows = "treefmt-nix";
    pyproject-nix.inputs.lix-unit.follows = "lix-unit";

    mdbook-nixdoc.url = "github:adisbladis/mdbook-nixdoc";
    mdbook-nixdoc.inputs.nixpkgs.follows = "nixpkgs";
    mdbook-nixdoc.inputs.nix-github-actions.follows = "nix-github-actions";

    lix-unit = {
      url = "github:adisbladis/lix-unit";
      inputs.mdbook-nixdoc.follows = "mdbook-nixdoc";
      inputs.nix-github-actions.follows = "nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      # flake-parts,
      treefmt-nix,
      pyproject-nix,
      nix-github-actions,
      lix-unit,
      ...
    }@inputs:
    let
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      inherit (nixpkgs) lib;
    in
    {

      # imports = [ treefmt-nix.flakeModule ];

      githubActions = nix-github-actions.lib.mkGithubMatrix {
        checks = {
          inherit (self.checks) x86_64-linux;
        };
      };

      lib = import ./lib {
        inherit pyproject-nix;
        inherit lib;
      };

      templates =
        let
          root = ./templates;
          dirs = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir root));
        in
        lib.listToAttrs (
          map (
            dir:
            let
              path = root + "/${dir}";
              template = import (path + "/flake.nix");
            in
            lib.nameValuePair dir {
              inherit path;
              inherit (template) description;
            }
          ) dirs
        );

      # Expose unit tests for external discovery
      libTests = import ./lib/test.nix {
        inherit lib pyproject-nix;
        uv2nix = self.lib;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          mkShell' =
            { nix-unit }:
            pkgs.mkShell {
              packages = [
                pkgs.hivemind
                pkgs.mdbook
                pkgs.reflex
                nix-unit
                inputs.mdbook-nixdoc.packages.${system}.default
                pkgs.uv
              ] ++ self.packages.${system}.doc.nativeBuildInputs;
            };
        in
        {
          nix = mkShell' { inherit (pkgs) nix-unit; };
          lix = mkShell' { nix-unit = lix-unit.packages.${system}.default; };
          default = self.devShells.${system}.nix;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        builtins.removeAttrs self.packages.${system} [ "default" ]
        // import ./dev/checks.nix {
          inherit pyproject-nix pkgs lib;
          uv2nix = self.lib;
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          doc = pkgs.callPackage ./doc {
            inherit self;
            mdbook-nixdoc = inputs.mdbook-nixdoc.packages.${system}.default;
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        (treefmt-nix.lib.evalModule pkgs ./dev/treefmt.nix).config.build.wrapper
      );
    };
}
