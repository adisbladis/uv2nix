{ pkgs }:
_final: prev: {

  # Wheels are automatically patched using autoPatchelfHook.
  #
  # For manylinux wheels the appropriate packages are added
  # as described in https://peps.python.org/pep-0599/ and various other PEPs.
  #
  # Some packages provide binary libraries as a part of their binary wheels,
  # others expect libraries to be provided by the system.
  #
  # Numba depends on libtbb, of a more recent version than nixpkgs provides in it's default tbb attribute.
  numba = prev.numba.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tbb_2021_11 ];
  });

}
