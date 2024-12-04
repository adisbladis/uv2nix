# Using `meta`

`uv2nix` primarily builds [_virtual environments_](https://docs.python.org/3/library/venv.html), not individual applications.

Virtual environment derivations have no concept of what their "main" binary is, meaning that a call like `lib.getExe` or a command like `nix run` won't know what is considered the main program.

To supplement `meta` fields in virtualenv derivations add an override:

``` nix
{
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
}
```
