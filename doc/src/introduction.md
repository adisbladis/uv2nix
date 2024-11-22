# Introduction

`uv2nix` takes a [`uv`](https://docs.astral.sh/uv/) [workspace](https://docs.astral.sh/uv/concepts/workspaces/) and generates Nix derivations dynamically using pure Nix code.
It's designed to be used both as a development environment manager, and to build production packages for projects.

It is heavily based on [`pyproject.nix`](https://pyproject-nix.github.io/pyproject.nix) and it's [build infrastructure](https://pyproject-nix.github.io/pyproject.nix/build.html).

Disclaimer: `uv2nix` is new and experimental.
