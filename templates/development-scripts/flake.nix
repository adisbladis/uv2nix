{
  description = "Using Nix Flake apps to run scripts with uv2nix";

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
      inherit (lib) filterAttrs hasSuffix;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel"; # or sourcePreference = "sdist";
      };

      pyprojectOverrides = _final: _prev: {
        # Implement build fixups here.
      };

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      python = pkgs.python312;

      pythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
            ]
          );

      venv = pythonSet.mkVirtualEnv "development-scripts-default-env" workspace.deps.default;
    in
    {

      apps.x86_64-linux =
        let
          # Example base directory
          basedir = ./examples;

          # Get a list of regular Python files in example directory
          files = filterAttrs (name: type: type == "regular" && hasSuffix ".py" name) (
            builtins.readDir basedir
          );

        in
        # Map over files to:
        # - Rewrite script shebangs as shebangs pointing to the virtualenv
        # - Strip .py suffixes from attribute names
        #   Making a script "greet.py" runnable as "nix run .#greet"
        lib.mapAttrs' (
          name: _:
          lib.nameValuePair (lib.removeSuffix ".py" name) (
            let
              script = basedir + "/${name}";

              # Patch script shebang
              program = pkgs.runCommand name { buildInputs = [ venv ]; } ''
                cp ${script} $out
                chmod +x $out
                patchShebangs $out
              '';
            in
            {
              type = "app";
              program = "${program}";
            }
          )
        ) files;

    };
}
