# pyproject.nix


Note that `uv2nix` is not using the Nixpkgs Python build infrastructure, but is instead using the [`pyproject.nix` build infrastructure](https://nix-community.github.io/pyproject.nix/build.html).


## flake.nix
```nix
{{#include ../../../templates/hello-world/flake.nix}}
```
