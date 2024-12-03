# Platform quirks

`pyproject.nix` tries to set reasonable platform defaults when evaluating [PEP-508](https://pyproject-nix.github.io/pyproject.nix/lib/pep508.html) markers & checking wheel compatibility.
There is platform metadata which is important to the Python dependency graph which may have to be overriden or supplemented from the inferred defaults.

For example Nixpkgs doesn't know which version of MacOS you're actually using. It only has information about what minimum SDK versions it supports & there is no way for Nix code to know which MacOS version you intend to target.

## Setting MacOS version

To override the MacOS SDK version used for marker evaluation & wheel compatibility checks override `darwinSdkVersion` in `stdenv.targetPlatform` in the original package set creation call:
```nix
pkgs.callPackage pyproject-nix.build.packages {
  inherit python;
  stdenv = pkgs.stdenv.override {
    targetPlatform = pkgs.stdenv.targetPlatform // {
      # Sets MacOS SDK version to 15.1 which implies Darwin version 24.
      # See https://en.wikipedia.org/wiki/MacOS_version_history#Releases for more background on version numbers.
      darwinSdkVersion = "15.1";
    };
  };
}
```

## Setting Linux kernel version for marker evaluations

Nixpkgs also doesn't know which Linux kernel you're actually targetting, but makes a reasonable guess from the `linuxHeaders` package.
To override the Linux kernel version used for marker evaluation in the call to `mkPyprojectOverlay`:

``` nix
let
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
    environ = {
      platform_release = "5.10.65";
    };
  }
in ...
```
