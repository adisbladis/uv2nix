{ uv2nix, lib }:

let
  inherit (lib)
    fix
    mapAttrs
    mapAttrs'
    toUpper
    substring
    stringLength
    length
    attrNames
    ;

  capitalise = s: toUpper (substring 0 1 s) + (substring 1 (stringLength s) s);

in

fix (self: {

  # Yo dawg, I heard you like tests...
  #
  # Check that all exported modules are covered by a test suite with at least one test.
  # TODO: Use addCoverage from nix-unit
  coverage = mapAttrs (
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
  ) uv2nix;
})
