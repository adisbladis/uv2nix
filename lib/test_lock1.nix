{
  lock1,
  lib,
  pkgs,
  pyproject-nix,
  ...
}:

let
  inherit (lib)
    findFirst
    mapAttrs
    mapAttrs'
    importTOML
    nameValuePair
    toUpper
    substring
    stringLength
    ;
  inherit (pyproject-nix.lib) pep508 pep621;
  inherit (builtins) baseNameOf;

  environs = {
    cpython312 = pyproject-nix.lib.pep508.mkEnviron pkgs.python312;
  };

  projectDirs = {
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
    multiPythons = ./fixtures/multi-pythons;
    no-build-no-binary-packages = ./fixtures/no-build-no-binary-packages;
  };

  projects = mapAttrs (
    _: dir: pyproject-nix.lib.project.loadUVPyproject { projectRoot = dir; }
  ) projectDirs;

  locks = mapAttrs (_: dir: importTOML (dir + "/uv.lock")) projectDirs;

  findFirstPkg = name: findFirst (package: package.name == name) (throw "Not found: ${name}");

  capitalise = s: toUpper (substring 0 1 s) + (substring 1 (stringLength s) s);

in

{
  parseLock = mapAttrs' (
    n: lock:
    let
      name = "test${capitalise n}";
    in
    nameValuePair name {
      expr =
        let
          result = lock1.parseLock lock;
        in
        assert result ? package;
        removeAttrs result [ "package" ];
      expected = lib.importJSON ./expected/lock1.parseLock.${name}.json;
    }
  ) locks;

  # Implicitly tested by parseLock
  parseManifest = {
    testDummy = {
      expr = null;
      expected = null;
    };
  };

  mkPackage =
    let

      # Return a callPackage'd package.
      mkPackageTest =
        {
          projectName,
          workspaceRoot ? projectDirs.${projectName},
          environ ? environs.cpython312,
          python ? pkgs.python312,
          sourcePreference,
        }:
        let
          mkPackage = lock1.mkPackage {
            inherit workspaceRoot environ sourcePreference;
            projects = lib.filterAttrs (n: _: n == projectName) projects;
          };
        in
        depName:
        python.pkgs.callPackage (mkPackage (
          lock1.parsePackage (findFirstPkg depName locks.${projectName}.package)
        )) { };

    in
    {
      testBuildNoBinaryPackagesPrefWheel = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "wheel";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };

      testBuildNoBinaryPackagesPrefSdist = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "sdist";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };
    };

  parsePackage =
    let
      parsePkg = name: fixture: lock1.parsePackage (findFirstPkg name fixture.package);
    in
    mapAttrs
      (name: expr: {
        expected = lib.importJSON ./expected/lock1.parsePackage.${name}.json;
        inherit expr;
      })
      {
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
        testWithExtra = parsePkg "with-extra" locks.withExtra;
      };

  filterPackage =
    let
      filterPkg =
        name: fixture: environ:
        let
          parsed = lock1.parsePackage (findFirstPkg name fixture.package);
        in
        lock1.filterPackage environ parsed;

    in
    mapAttrs
      (name: expr: {
        inherit expr;
        expected = lib.importJSON ./expected/lock1.filterPackage.${name}.json;
      })
      {
        testMultiChoicePackage =
          filterPkg "multi-choice-package" locks.multiChoicePackage
            environs.cpython312;
        testOptionalDeps = filterPkg "optional-deps" locks.optionalDeps environs.cpython312;
        testDevDeps = filterPkg "with-tool-uv-devdeps" locks.withToolUvDevDeps environs.cpython312;
      };

  resolveDependencies =
    let
      testResolve =
        projectName:
        {
          interpreter ? pkgs.python312,
        }:
        let
          project = projects.${projectName};
          environ = pep508.mkEnviron interpreter;

          resolved = lock1.resolveDependencies {
            dependencies = pep621.filterDependenciesByEnviron environ [ ] project.dependencies;
            lock = lock1.parseLock locks.${projectName};
            inherit environ;
          };
        in
        mapAttrs (name: package: package.name + "-" + package.version) resolved; # Make expected only contain relevent data

    in
    mapAttrs
      (name: expr: {
        expected = lib.importJSON ./expected/lock1.resolveDependencies.${name}.json;
        inherit expr;
      })
      {
        testTrivial = testResolve "trivial" { };
        testMultiChoicePackage = testResolve "multiChoicePackage" { };
        testResolveWithOptionals = testResolve "optionalDeps" { };
        testResolveNoOptionals = testResolve "optionalDeps" { };
        testDevDeps = testResolve "withToolUvDevDeps" { };
        testResolveKitchenSink = testResolve "kitchenSinkA" { };
        testMultiPythons = testResolve "multiPythons" { };
      };
}
