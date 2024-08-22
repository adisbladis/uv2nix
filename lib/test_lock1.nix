{ lock1, lib, pkgs, pyproject-nix, ... }:

let
  inherit (lib) findFirst mapAttrs mapAttrs' importTOML nameValuePair toUpper substring stringLength;

  environs = {
    cpython312 = pyproject-nix.lib.pep508.mkEnviron pkgs.python312;
  };

  locks = mapAttrs (_: dir: importTOML (dir + "/uv.lock")) {
    workspace = ./fixtures/workspace;
    kitchenSinkA = ./fixtures/kitchen-sink/a;
    kitchenSinkCEditable = ./fixtures/kitchen-sink/c-editable;
    kitchenSinkB = ./fixtures/kitchen-sink/b;
    withExtra = ./fixtures/with-extra;
    trivial = ./fixtures/trivial;
    multiChoicePackage = ./fixtures/multi-choice-package;
    workspaceFlat = ./fixtures/workspace-flat;
    optionalDeps = ./fixtures/optional-deps;
    noDeps = ./fixtures/no-deps;
    withToolUvDevDeps = ./fixtures/with-tool-uv-devdeps;
    withResolverOptions = ./fixtures/with-resolver-options;
    withSupportedEnvironments = ./fixtures/with-supported-environments;
  };

  findFirstPkg = name: findFirst (package: package.name == name) (throw "Not found: ${name}");

  capitalise = s: toUpper (substring 0 1 s) + (substring 1 (stringLength s) s);

in

{
  parseLock = mapAttrs' (n: lock: let
    name = "test${capitalise n}";
  in nameValuePair name {
    expr = let
      result = lock1.parseLock lock;
    in assert result ? package; removeAttrs result [ "package" ];
    expected = lib.importJSON ./expected/lock1.parseLock.${name}.json;
  }) locks;

  # Implicitly tested by parseLock
  parseManifest = {
    testDummy = {
      expr = null;
      expected = null;
    };
  };

  parsePackage =
    let
      parsePkg = name: fixture: lock1.parsePackage (findFirstPkg name fixture.package);
    in
      mapAttrs (name: expr: {
        expected = lib.importJSON ./expected/lock1.parsePackage.${name}.json;
        inherit expr;
      }) {
      # Trivial "smoke test"
      testTrivial = parsePkg "arpeggio" locks.trivial;
      # A test for a package with many metadata.requires-dist types
      testMetadataRequiresDistMany = parsePkg "a" locks.kitchenSinkA;
      testWheelURL = parsePkg "arpeggio" locks.kitchenSinkA;
      testSdistURL = parsePkg "blinker" locks.kitchenSinkA;
      testGitURL = parsePkg "pip" locks.kitchenSinkA;
      testLocal = parsePkg "b" locks.kitchenSinkA;
      testLocalSdist = parsePkg "attrs" locks.kitchenSinkA;
      testLocalEditable = parsePkg "c-editable" locks.kitchenSinkA;
      testWithResolutionMarkers = parsePkg "arpeggio" locks.multiChoicePackage;
      testOptionalDeps = parsePkg "optional-deps" locks.optionalDeps;
      testMetadataRequiresDev = parsePkg "with-tool-uv-devdeps" locks.withToolUvDevDeps;
      testWithResolverOptions = parsePkg "arpeggio" locks.withResolverOptions;
    };

  filterPackage = let
    filterPkg = name: fixture: environ: let
      parsed = lock1.parsePackage (findFirstPkg name fixture.package);
    in lock1.filterPackage environ parsed;

    in mapAttrs (name: expr: {
      inherit expr;
      expected = lib.importJSON ./expected/lock1.filterPackage.${name}.json;
    }) {
      testMultiChoicePackage = filterPkg "multi-choice-package" locks.multiChoicePackage environs.cpython312;
      testOptionalDeps = filterPkg "optional-deps" locks.optionalDeps environs.cpython312;
      testDevDeps = filterPkg "with-tool-uv-devdeps" locks.withToolUvDevDeps environs.cpython312;

    };
}
