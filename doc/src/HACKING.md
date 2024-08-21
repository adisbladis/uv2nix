# Hacking

This document outlines hacking on `uv2nix` itself, and lays out it's project structure.

## Project structure & testing

All Nix code lives in `lib/`. Each file has an implementation and a test suite.
The attribute path to a an attribute `mkOverlay` in `lib/lock.nix` would be `lib.lock.mkOverlay`.

A function in `lib/test.nix` maps over the public interface of the library and the test suite to generate coverage tests, ensuring that every exported symbol has at least one test covering it.

Integration tests meaning tests that perform environment constructions & builds lives in `test/` and are exposed through Flake checks.

The manual you are reading right now is built from the `doc/` directory.
To edit a specific page see the "Edit this page on GitHub" link in the footer for each respective page.

## Running tests

- Run the entire unit test suite
  `$ nix-unit --flake .#libTests`

- Run unit tests for an individual function
  `$ nix-unit --flake .#libTests.lock.mkOverlay

- Run integration tests
  `$ nix flake check`

## Formatter

Before submitting a PR format the code with `nix fmt` and ensure Flake checks pass with `nix flake check`.
