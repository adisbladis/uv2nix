final: prev:
let
  inherit (final) resolveBuildSystem;
  inherit (builtins) mapAttrs;

  # Build system dependencies specified in the shape expected by resolveBuildSystem
  # The empty lists below are lists of optional dependencies.
  #
  # A package `foo` with specification written as:
  # `setuptools-scm[toml]` in pyproject.toml would be written as
  # `foo.setuptools-scm = [ "toml" ]` in Nix
  buildSystemOverrides = {
    arpeggio = {
      setuptools = [ ];
      pytest-runner = [ ];
    };
    attrs = {
      hatchling = [ ];
      hatch-vcs = [ ];
      hatch-fancy-pypi-readme = [ ];
    };
    tomli.flit-core = [ ];
    coverage.setuptools = [ ];
    blinker.setuptools = [ ];
    certifi.setuptools = [ ];
    charset-normalizer.setuptools = [ ];
    idna.flit-core = [ ];
    urllib3 = {
      hatchling = [ ];
      hatch-vcs = [ ];
    };
    pip = {
      setuptools = [ ];
      wheel = [ ];
    };
    packaging.flit-core = [ ];
    requests.setuptools = [ ];
    pysocks.setuptools = [ ];
    pytest-cov.setuptools = [ ];
    tqdm.setuptools = [ ];
  };

in
mapAttrs (
  name: spec:
  prev.${name}.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ resolveBuildSystem spec;
  })
) buildSystemOverrides
