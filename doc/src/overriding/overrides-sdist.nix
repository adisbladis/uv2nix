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
    # Pyproject.nix's build-system-pkgs contains some of the most
    # important build systems already, so you don't have to add these to your project.
    #
    # For a comprehensive list see
    # https://github.com/pyproject-nix/build-system-pkgs/blob/master/pyproject.toml
    #
    # For build-systems that are not present in this list you can either:
    # - Add it to your `uv` project
    # - Add it manually in an overlay
    # - Submit a PR to build-system-pkgs adding the build system
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
