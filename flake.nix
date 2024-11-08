{
  description = "Uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

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

      githubActions = nix-github-actions.lib.mkGithubMatrix {
        checks =
          let
            strip = lib.flip removeAttrs [
              # No need to run formatter check on multiple platforms
              "formatter"
            ];
          in
          {
            inherit (self.checks) x86_64-linux;
            aarch64-darwin = strip self.checks.aarch64-darwin;
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
                self.packages.${system}.uv-bin
                pkgs.python3
                self.formatter.${system}
              ] ++ self.packages.${system}.doc.nativeBuildInputs;

              shellHook = ''
                export UV_NO_SYNC=1
              '';
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
        //
          # Test flake templates
          (
            let

              inherit (builtins) mapAttrs functionArgs;

              # Call a nested flake with the inputs from this one.
              callFlake =
                path:
                let
                  flake' = import (path + "/flake.nix");
                  args = mapAttrs (name: _: inputs'.${name}) (functionArgs flake'.outputs);

                  flake = flake'.outputs args;

                  inputs' = inputs // {
                    uv2nix = self;
                    self = flake;
                  };
                in
                flake;

            in
            lib.listToAttrs (
              lib.concatLists (
                lib.mapAttrsToList (
                  template: _:
                  let
                    flake = callFlake (./templates + "/${template}");
                    mkChecks =
                      prefix: attr:
                      lib.mapAttrsToList (check: drv: lib.nameValuePair "template-${template}-${prefix}-${check}" drv) (
                        flake.${attr}.${system} or { }
                      );
                  in
                  mkChecks "check" "checks" ++ mkChecks "package" "packages" ++ mkChecks "devShell" "devShells"
                ) (builtins.readDir ./templates)
              )
            )
          )
        // {
          formatter =
            pkgs.runCommand "fmt-check"
              {
                nativeBuildInputs = [ self.formatter.${system} ];
              }
              ''
                cp -r ${self} $(stripHash "${self}")
                chmod -R +w .
                cd source
                treefmt --fail-on-change
                touch $out
              '';
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

          uv-bin = pkgs.callPackage ./pkgs/uv-bin { };
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
