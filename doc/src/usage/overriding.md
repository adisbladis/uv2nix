# Overriding

For more detailed information on overriding, see [`pyproject.nix`](https://nix-community.github.io/pyproject.nix/builders/overriding.html).

## Overriding sdist's (source builds)
```nix
{{#include ../../../templates/overriding/overrides-sdist.nix}}
```

The proper solution for this would be for [`uv` to lock build systems](https://github.com/astral-sh/uv/issues/5190).

## Overriding wheels (pre-built binaries)
```nix
{{#include ../../../templates/overriding/overrides-wheels.nix}}
```

Long term this situation could be improved by [PEP-725](https://peps.python.org/pep-0725/).

## pyproject.toml
```toml
{{#include ../../../templates/overriding/pyproject.toml}}
```

## Resources
- [`uv2nix` FAQ on overrides](../FAQ.md#why-doesnt-uv2nix-come-with-overrides)
- [`pyproject.nix` overriding docs](https://nix-community.github.io/pyproject.nix/builders/overriding.html).
- [`pyproject.nix` override hacks](https://nix-community.github.io/pyproject.nix/builders/hacks.html).

  Override utility functions

- [`uv2nix_hammer_overrides`](https://github.com/TyberiusPrime/uv2nix_hammer_overrides/)

  Third party overrides collection
