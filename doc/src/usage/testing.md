# Testing

`uv2nix` uses the [`pyproject.nix` build infrastructure](https://nix-community.github.io/pyproject.nix/build.html).

Unlike the nixpkgs, runtime & test dependencies are not available at build time.
Tests should instead be implemented as separate derivations.

This example shows:
- Overriding a package adding tests to `passthru.tests`
- Using `passthru.tests` in Flake checks

## flake.nix
```nix
{{#include ../../../templates/testing/flake.nix}}
```
## pyproject.toml
```nix
{{#include ../../../templates/testing/pyproject.toml}}
```
