{
  description = "Uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      ...
    }@inputs:
    let
      npins = import ./npins;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      inherit (nixpkgs) lib;
    in
    {

      githubActions = (import npins.nix-github-actions).mkGithubMatrix {
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
                pkgs.mdbook-cmdrun
                self.packages.${system}.uv-bin
                pkgs.python3
                self.formatter.${system}
                pkgs.npins
              ] ++ self.packages.${system}.doc.nativeBuildInputs;

              shellHook = ''
                export UV_NO_SYNC=1
              '';
            };
        in
        {
          nix = mkShell' { inherit (pkgs) nix-unit; };

          lix = mkShell' {
            nix-unit =
              let
                lix = pkgs.lixVersions.latest;
              in
              (pkgs.nix-unit.override {
                # Hacky overriding :)
                nixVersions = lib.mapAttrs (_n: _v: lix) pkgs.nixVersions;
                # nix = pkgs.lixVersions.latest;
              }).overrideAttrs
                (_old: {
                  pname = "lix-unit";
                  name = "lix-unit-${lix.version}";
                  inherit (lix) version;
                  src = npins.lix-unit;
                });
          };

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
                export HOME=$(mktemp -d)
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
          };

          uv-bin = pkgs.callPackage ./pkgs/uv-bin { };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.callPackage ./treefmt.nix { }
      );
    };
}
