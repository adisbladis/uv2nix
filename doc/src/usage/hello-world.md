# Hello world

This example shows you how to set up a Uv workspace using `uv2nix`.

It has the following features:
- Creating package set from `uv.lock`

- Development shells
  - One using `nix` to manage virtual environments

    With dependencies installed in editable mode.

  - One using `uv` to manage virtual environments

## flake.nix
```nix
{{#include ../../../templates/hello-world/flake.nix}}
```
## pyproject.toml
```nix
{{#include ../../../templates/hello-world/pyproject.toml}}
```

## Notes

In the interest of keeping documentation conceptually simple, no Flakes framework such as `flake-utils` or `flake-parts` are being used for this example.
