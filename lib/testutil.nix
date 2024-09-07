{ lib }:
let
  inherit (lib)
    toUpper
    substring
    stringLength
    ;
in
{
  capitalise = s: toUpper (substring 0 1 s) + (substring 1 (stringLength s) s);
}
