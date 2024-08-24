# FAQ

## My package $foo doesn't build!

`uv2nix` can only work with what it has, and `uv.lock` metadata is notably absent of important metadata.

Take a lock file entry for `requests` as an example:
``` toml
[[package]]
name = "pyzmq"
version = "26.2.0"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "cffi", marker = "implementation_name == 'pypy'" },
]
sdist = { url = "https://files.pythonhosted.org/packages/fd/05/bed626b9f7bb2322cdbbf7b4bd8f54b1b617b0d2ab2d3547d6e39428a48e/pyzmq-26.2.0.tar.gz", hash = "sha256:070672c258581c8e4f640b5159297580a9974b026043bd4ab0470be9ed324f1f", size = 271975 }
wheels = [
    { url = "https://files.pythonhosted.org/packages/28/2f/78a766c8913ad62b28581777ac4ede50c6d9f249d39c2963e279524a1bbe/pyzmq-26.2.0-cp312-cp312-macosx_10_15_universal2.whl", hash = "sha256:ded0fc7d90fe93ae0b18059930086c51e640cdd3baebdc783a695c77f123dcd9", size = 1343105 },
    # More binary wheels removed for brevity
]
```

And contrast it with a minimal Nix `buildPythonPackage` example to build the same package:
``` nix
buildPythonPackage rec {
  pname = "pyzmq";
  version = "26.2.0";
  pyproject = true;
  src = fetchPypi {
    inherit pname version;
    hash = "sha256:070672c258581c8e4f640b5159297580a9974b026043bd4ab0470be9ed324f1f";
  };
  build-system = [
    cmake
    ninja
    packaging
    pathspec
    scikit-build-core
  ] ++ (if isPyPy then [ cffi ] else [ cython ]);
  dontUseCmakeConfigure = true;
  buildInputs = [ zeromq ];
  dependencies = lib.optionals isPyPy [ cffi ];
}
```

Notably absent from `uv.lock` are:

- Native libraries

When building binary wheels `uv2nix` uses [https://nixos.org/manual/nixpkgs/stable/#setup-hook-autopatchelfhook](autoPatchelfHook).
This patches RPATH's of wheels with native libraries, but those must be present at build time.

- [PEP-517](https://peps.python.org/pep-0517/) build systems

Uv, like most Python package managers, installs binary wheels by default, and it's solver doesn't take into account bootstrapping dependencies.
When building from an sdist instead of a wheel build systems will need to be added.

This is is dealt with by [overrides](https://nixos.org/manual/nixpkgs/stable/#overriding-python-packages).
