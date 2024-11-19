{
  description = "Django application using uv2nix";

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

  outputs =
    {
      self,
      nixpkgs,
      uv2nix,
      pyproject-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      asgiApp = "django_webapp.asgi:application";
      settingsModules = {
        prod = "django_webapp.settings";
      };

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

          # Base Python package set from pyproject.nix
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python312;
          };

          # An overlay of build fixups & test additions
          pyprojectOverrides = final: prev: {

            # django-webapp is the name of our example package
            django-webapp = prev.django-webapp.overrideAttrs (old: {

              # Add tests to passthru.tests
              #
              # These attribute are used in Flake checks.
              passthru = old.passthru // {
                tests =
                  (old.tests or { })
                  // {

                    # Run mypy checks
                    mypy =
                      let
                        venv = final.mkVirtualEnv "django-webapp-typing-env" {
                          django-webapp = [ "typing" ];
                        };
                      in
                      stdenv.mkDerivation {
                        name = "${final.django-webapp.name}-mypy";
                        inherit (final.django-webapp) src;
                        nativeBuildInputs = [
                          venv
                        ];
                        dontConfigure = true;
                        dontInstall = true;
                        buildPhase = ''
                          mkdir $out
                          mypy --strict . --junit-xml $out/junit.xml
                        '';
                      };

                    # Run pytest with coverage reports installed into build output
                    pytest =
                      let
                        venv = final.mkVirtualEnv "django-webapp-pytest-env" {
                          django-webapp = [ "test" ];
                        };
                      in
                      stdenv.mkDerivation {
                        name = "${final.django-webapp.name}-pytest";
                        inherit (final.django-webapp) src;
                        nativeBuildInputs = [
                          venv
                        ];

                        dontConfigure = true;

                        buildPhase = ''
                          runHook preBuild
                          pytest --cov tests --cov-report html tests
                          runHook postBuild
                        '';

                        installPhase = ''
                          runHook preInstall
                          mv htmlcov $out
                          runHook postInstall
                        '';
                      };
                  }
                  // lib.optionalAttrs stdenv.isLinux {

                    # NixOS module test
                    nixos =
                      let
                        venv = final.mkVirtualEnv "django-webapp-nixos-test-env" {
                          django-webapp = [ ];
                        };
                      in
                      pkgs.nixosTest {
                        name = "django-webapp-nixos-test";

                        nodes.machine =
                          { ... }:
                          {
                            imports = [
                              self.nixosModules.django-webapp
                            ];

                            services.django-webapp = {
                              enable = true;
                              inherit venv;
                            };

                            system.stateVersion = "24.11";
                          };

                        testScript = ''
                          machine.wait_for_unit("django-webapp.service")

                          with subtest("Web interface getting ready"):
                              machine.wait_until_succeeds("curl -fs localhost:8000")
                        '';
                      };

                  };
              };
            });

          };

        in
        baseSet.overrideScope (lib.composeExtensions overlay pyprojectOverrides)
      );

      # Django static roots grouped per system
      staticRoots = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) stdenv;

          pythonSet = pythonSets.${system};

          venv = pythonSet.mkVirtualEnv "django-webapp-env" workspace.deps.default;

        in
        stdenv.mkDerivation {
          name = "django-webapp-static";
          inherit (pythonSet.django-webapp) src;

          dontConfigure = true;
          dontBuild = true;

          nativeBuildInputs = [
            venv
          ];

          installPhase = ''
            env DJANGO_STATIC_ROOT="$out" python manage.py collectstatic
          '';
        }
      );

    in
    {
      checks = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};
        in
        # Inherit tests from passthru.tests into flake checks
        pythonSet.django-webapp.passthru.tests
      );

      nixosModules = {
        django-webapp =
          {
            config,
            lib,
            pkgs,
            ...
          }:

          let
            cfg = config.services.django-webapp;
            inherit (pkgs) system;

            pythonSet = pythonSets.${system};

            inherit (lib.options) mkOption;
            inherit (lib.modules) mkIf;
          in
          {
            options.services.django-webapp = {
              enable = mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Enable django-webapp
                '';
              };

              settings-module = mkOption {
                type = lib.types.string;
                default = settingsModules.prod;
                description = ''
                  Django settings module
                '';
              };

              venv = mkOption {
                type = lib.types.package;
                default = pythonSet.mkVirtualEnv "django-webapp-env" workspace.deps.default;
                description = ''
                  Django-webapp virtual environment package
                '';
              };

              static-root = mkOption {
                type = lib.types.package;
                default = staticRoots.${system};
                description = ''
                  Django-webapp static root
                '';
              };
            };

            config = mkIf cfg.enable {
              systemd.services.django-webapp = {
                description = "Django Webapp server";

                environment.DJANGO_STATIC_ROOT = cfg.static-root;

                serviceConfig = {
                  ExecStart = ''
                    ${cfg.venv}/bin/daphne django_webapp.asgi:application
                  '';
                  Restart = "on-failure";

                  DynamicUser = true;
                  StateDirectory = "django-webapp";
                  RuntimeDirectory = "django-webapp";

                  BindReadOnlyPaths = [
                    "${
                      config.environment.etc."ssl/certs/ca-certificates.crt".source
                    }:/etc/ssl/certs/ca-certificates.crt"
                    builtins.storeDir
                    "-/etc/resolv.conf"
                    "-/etc/nsswitch.conf"
                    "-/etc/hosts"
                    "-/etc/localtime"
                  ];
                };

                wantedBy = [ "multi-user.target" ];
              };
            };

          };

      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pythonSet = pythonSets.${system};
        in
        lib.optionalAttrs pkgs.stdenv.isLinux {
          # Expose Docker container in packages
          docker =
            let
              venv = pythonSet.mkVirtualEnv "django-webapp-env" workspace.deps.default;
            in
            pkgs.dockerTools.buildLayeredImage {
              name = "django-webapp";
              contents = [ pkgs.cacert ];
              config = {
                Cmd = [
                  "${venv}/bin/daphne"
                  asgiApp
                ];
                Env = [
                  "DJANGO_SETTINGS_MODULE=${settingsModules.prod}"
                  "DJANGO_STATIC_ROOT=${staticRoots.${system}}"
                ];
              };
            };
        }
      );

      # Use an editable Python set for development.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          editablePythonSet = pythonSets.${system}.overrideScope editableOverlay;
          venv = editablePythonSet.mkVirtualEnv "django-webapp-dev-env" {
            django-webapp = [ "dev" ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              venv
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
