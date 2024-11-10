# FAQ

## My package $foo doesn't build!

`uv2nix` can only work with what it has, and `uv.lock` metadata is notably absent of important metadata.

For more details see [overriding](./usage/overriding.md).

## Why doesn't uv2nix come with overrides?

Users coming from [poetry2nix](https://github.com/nix-community/poetry2nix) may be surprised to find that uv2nix doesn't come with any bundled overrides.

Overrides are required because Python tooling is lacking important metadata, complexity which surfaces when using Nix.
Uv2nix focuses on getting the translation from `pyproject.toml` & `uv.lock` to Nix right, without trying to taper over deficiencies in metadata.

In poetry2nix much of the requirement of overriding came from it's choice to build sdist's by default.
uv2nix doesn't have a default package source preference, instead requiring users to make that choice.
Binary wheels are much more likely to "just work", making it feasible to use uv2nix without an overrides collection at all.
Maintaining overrides was the [biggest source of maintainer burnout for poetry2nix](https://github.com/nix-community/poetry2nix/issues/1865#issue-2640023203).

Users will either have to maintain their own set of overrides, or use a third-party override collection.
