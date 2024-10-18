{
  pyproject-nix,
  uv2nix,
  lib,
  pkgs,
}:

let
  inherit (lib)
    fix
    mapAttrs
    mapAttrs'
    length
    attrNames
    ;
  inherit (import ./testutil.nix { inherit lib; }) capitalise;

  callTest = path: import path (uv2nix // { inherit pkgs lib pyproject-nix; });

in

fix (self: {
  lock1 = callTest ./test_lock1.nix;
  workspace = callTest ./test_workspace.nix;
  renderers = callTest ./test_renderers.nix;

  # Yo dawg, I heard you like tests...
  #
  # Check that all exported modules are covered by a test suite with at least one test.
  # TODO: Use addCoverage from nix-unit
  coverage =
    mapAttrs
      (
        moduleName:
        mapAttrs' (
          sym: _: {
            name = "test" + capitalise sym;
            value = {
              expected = true;
              expr = self ? ${moduleName}.${sym} && length (attrNames self.${moduleName}.${sym}) >= 1;
            };
          }
        )
      )
      (
        removeAttrs uv2nix [
          # Exclude build module from coverage
          "build"
        ]
      );
})
