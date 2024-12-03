# Overriding build systems

Overriding many build systems manually can quickly become tiresome with repeated declerations of `nativeBuildInputs` & calls to `resolveBuildSystem` for every package.

This overlay shows one strategy to deal with many build system overrides in a declarative fashion.

```nix
{{#include ../../../dev/build-system-overrides.nix}}
```
