# Development scripts

It's common to have development scripts that you don't want to publish in a Python package, but that you might want to run ergonomically from Nix.

This pattern shows how to:
- Take a directory of development scripts (`examples/`)
- Wrap the scripts in a virtualenv
- Make scripts runnable using `nix run`

## `flake.nix`

```nix
{{#include ../../../templates/development-scripts/flake.nix}}
```
