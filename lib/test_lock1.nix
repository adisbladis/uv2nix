{ lock1, lib, ... }:

let
  inherit (lib) findFirst mapAttrs mapAttrs' importTOML nameValuePair toUpper substring stringLength;

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
      mapAttrs (name: case: case // {
        expected = lib.importJSON ./expected/lock1.parsePackage.${name}.json;
      }) {
      # Trivial "smoke test"
      testTrivial = {
        expr = parsePkg "arpeggio" locks.trivial;
        expected = null;
      };

      # A test for a package with many metadata.requires-dist types
      testMetadataRequiresDistMany = {
        expr = parsePkg "a" locks.kitchenSinkA;
        expected = null;
      };

      testWheelURL = {
        expr = parsePkg "arpeggio" locks.kitchenSinkA;
        expected = null;
      };

      testSdistURL = {
        expr = parsePkg "blinker" locks.kitchenSinkA;
        expected = null;
      };

      testGitURL = {
        expr = parsePkg "pip" locks.kitchenSinkA;
        expected = null;
      };

      testLocal = {
        expr = parsePkg "b" locks.kitchenSinkA;
        expected = null;
      };

      testLocalSdist = {
        expr = parsePkg "attrs" locks.kitchenSinkA;
        expected = null;
      };

      testLocalEditable = {
        expr = parsePkg "c-editable" locks.kitchenSinkA;
        expected = null;
      };

      testWithResolutionMarkers = {
        expr = parsePkg "arpeggio" locks.multiChoicePackage;
        expected = null;
      };

      testOptionalDeps = {
        expr = parsePkg "optional-deps" locks.optionalDeps;
        expected = null;
      };

      testMetadataRequiresDev = {
        expr = parsePkg "with-tool-uv-devdeps" locks.withToolUvDevDeps;
        expected = null;
      };

      testWithResolverOptions = {
        expr = parsePkg "arpeggio" locks.withResolverOptions;
        expected = null;
      };
    };

}
