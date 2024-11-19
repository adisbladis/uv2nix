{ pkgs }:
final: prev: {

  pyzmq = prev.pyzmq.overrideAttrs (old: {

    # Use the zeromq library from nixpkgs.
    #
    # If not provided by the system pyzmq will build a zeromq library
    # as a part of it's package build, taking unnecessary time & effort.
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.zeromq ];

    # uv.lock does not contain build-system metadata.
    # Meaning that for source builds, this needs to be provided by overriding.
    #
    # Pyproject.nix contains some of the most important build-system's already,
    # so you don't have to add these to your project.
    #
    # For a comprehensive list see
    # https://github.com/pyproject-nix/pyproject.nix/tree/master/build/pkgs
    #
    # For build-systems that are not present in this list you can either:
    # - Add it to your `uv` project
    # - Add it manually in an overlay
    # - Submit a PR to pyproject.nix adding the system
    #   This will potentially be rejected.
    #   Pyproject.nix only aims to contain a base set.
    nativeBuildInputs = old.nativeBuildInputs ++ [
      (final.resolveBuildSystem {
        cmake = [ ];
        ninja = [ ];
        packaging = [ ];
        pathspec = [ ];
        scikit-build-core = [ ];
        cython = [ ];
      })
    ];

  });

}
