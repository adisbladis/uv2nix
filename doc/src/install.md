# Installation

## Classic Nix

Documentation examples in `uv2nix` are using Flakes for the convenience of grouping multiple concepts into a single file.

You can just as easily import `uv2nix` without using Flakes:
``` nix
let
  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;

  pyproject-nix = import (builtins.fetchGit {
    url = "https://github.com/pyproject-nix/pyproject.nix.git";
  }) {
    inherit lib;
  };

  uv2nix = import (builtins.fetchGit {
    url = "https://github.com/pyproject-nix/uv2nix.git";
  }) {
    inherit pyproject-nix lib;
  };

  pyproject-build-systems = import (builtins.fetchGit {
    url = "https://github.com/pyproject-nix/build-system-pkgs.git";
  }) {
    inherit pyproject-nix uv2nix lib;
  };

in
  ...
```

## Flakes

See [usage/hello-world](usage/hello-world.md).
