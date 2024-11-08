# Django

Building on the previous simple testing example we're building a web application using Django.

This example aims to be a showcase of many different capabilities & possibilites of `uv2nix`:

- Packaging a web application using Django

- Using Django's [staticfiles](https://docs.djangoproject.com/en/5.1/howto/static-files/) app

- Constructing Docker containers

  Using `dockerTools` from nixpkgs.

- Creating NixOS modules for `uv2nix` apps

  With accompanying NixOS tests.

  A real-world deployment should use a reverse proxy, for example `nginx`.
  Use this documentation as inspiration, not as a best practices guide.

## flake.nix
```nix
{{#include ../../../templates/django-webapp/flake.nix}}
```

## pyproject.toml
```nix
{{#include ../../../templates/django-webapp/pyproject.toml}}
```
