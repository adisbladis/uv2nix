{
  description = "A basic flake using uv2nix";

  inputs.uv2nix.url = "github:adisbladis/uv2nix";
  inputs.uv2nix.inputs.nixpkgs.follows = "nixpkgs";

  # Disclaimer: Uv2nix is new and experimental.
  # Users are expected to be able to contribute fixes.

  outputs =
    { nixpkgs, uv2nix, ... }:
    let
      inherit (nixpkgs) lib;

      # Load a uv workspace from a workspace root.
      # Uv2nix treats all uv projects as workspace projects.
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      # Manage overlays
      overlay =
        let
          # Create overlay using pdm2nix
          overlay' = workspace.mkOverlay {
            # Prefer prebuilt binary wheels as a package source.
            # Sdists are less likely to "just work" because of the metadata missing from uv.lock.
            # Binary wheels are more likely to, but may still require overrides for library dependencies.
            sourcePreference = "wheel"; # or sourcePreference = "sdist";
          };

          # Uv2nix can only work with what it has, and uv.lock is missing essential metadata to perform some builds.
          # This is an additional overlay implementing build fixups.
          # See:
          # - https://adisbladis.github.io/uv2nix/FAQ.html
          # - https://nixos.org/manual/nixpkgs/stable/#overriding-python-packages
          overrides = _final: _prev: {
            # Add custom overrides here
          };
        in
        lib.composeExtensions overlay' overrides;

      # This example is only using x86_64-linux
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Create an overriden interpreter
      python = pkgs.python3.override {
        # Note the self argument.
        # It's important so the interpreter/set is internally consistent.
        self = python;
        # Pass composed Python overlay to the interpreter
        packageOverrides = overlay;
      };

      # Create a Python environment using withPackages
      pythonEnv = python.withPackages (_ps: [ ]);

    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell { packages = [ pythonEnv ]; };
    };
}
