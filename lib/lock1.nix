{ pyproject-nix, lib, ... }:

let
  inherit (pyproject-nix.lib.pep508) parseMarkers evalMarkers;
  inherit (pyproject-nix.lib.pypa) parseWheelFileName;
  inherit (pyproject-nix.lib) pep440;
  inherit (builtins) baseNameOf toJSON;
  inherit (lib)
    mapAttrs
    fix
    filter
    length
    all
    groupBy
    concatMap
    attrValues
    concatLists
    genericClosure
    isAttrs
    isList
    attrNames
    typeOf
    elem
    head
    listToAttrs
    any
    ;

in

fix (self: {

  /*
    Resolve dependencies from uv.lock
    .
  */
  resolveDependencies =
    {
      # Lock file as parsed by parseLock
      lock,
      # PEP-508 environment as returned by pyproject-nix.lib.pep508.mkEnviron
      environ,
      # Top-level project dependencies:
      # - as parsed by pyproject-nix.lib.pep621.parseDependencies
      # - as filtered by pyproject-nix.lib.pep621.filterDependencies
      dependencies,
    }:
    let
      # Evaluate top-level resolution-markers
      resolution-markers = mapAttrs (_: evalMarkers environ) lock.resolution-markers;

      # Filter dependencies of packages
      packages = map (self.filterPackage environ) (
        # Filter packages based on resolution-markers
        filter (
          pkg:
          length pkg.resolution-markers == 0
          || any (markers: resolution-markers.${markers}) pkg.resolution-markers
        ) lock.package
      );

      # Group list of package candidates by package name (pname)
      candidates = groupBy (pkg: pkg.name) packages;

      # Group list of package candidates by qualified package name (pname + version)
      allCandidates = groupBy (pkg: "${pkg.name}-${pkg.version}") packages;

      # Make key return for genericClosure
      mkKey = package: {
        key = "${package.name}-${package.version}";
        inherit package;
      };

      # Filter top-level deps for genericClosure startSet
      filterTopLevelDeps =
        deps:
        map mkKey (
          concatMap (
            dep:
            filter (
              pkg: all (spec: pep440.comparators.${spec.op} pkg.version' spec.version) dep.conditions
            ) candidates.${dep.name}
          ) deps
        );

      depNames = attrNames allDependencies;

      # Resolve dependencies recursively
      allDependencies = groupBy (dep: dep.package.name) (genericClosure {
        # Recurse into top-level dependencies.
        startSet =
          filterTopLevelDeps dependencies.dependencies
          ++ filterTopLevelDeps (concatLists (attrValues dependencies.extras))
          ++ filterTopLevelDeps (concatLists (attrValues dependencies.groups));

        operator =
          { key, ... }:
          # Note: Markers are already filtered.
          # Consider: Is it more efficient to only do marker filtration at resolve time, no pre-filtering?
          concatMap (
            candidate:
            map mkKey (
              concatMap
                (
                  dep: filter (package: dep.version == null || dep.version == package.version) candidates.${dep.name}
                )
                (
                  candidate.dependencies
                  ++ (concatLists (attrValues candidate.optional-dependencies))
                  ++ (concatLists (attrValues candidate.dev-dependencies))
                )
            )
          ) allCandidates.${key};
      });

      # Reduce dependency candidates down to the one resolved dependency.
      reduceDependencies =
        attrs:
        let
          result = mapAttrs (
            name: candidates:
            if isAttrs candidates then
              candidates # Already reduced
            else if length candidates == 1 then
              (head candidates).package
            # Ambigious, filter further
            else
              let
                # Get version declarations for this package from all other packages
                versions = concatMap (
                  n:
                  let
                    package = attrs.${n};
                  in
                  if isList package then
                    map (pkg: pkg.version) (
                      concatMap (pkg: filter (x: x.name == name) pkg.package.dependencies) package
                    )
                  else if isAttrs package then
                    map (pkg: pkg.version) (filter (x: x.name == name) package.dependencies)
                  else
                    throw "Unhandled type: ${typeOf package}"
                ) depNames;
                # Filter candidates by possible versions
                filtered =
                  if length versions > 0 then
                    filter (candidate: elem candidate.package.version versions) candidates
                  else
                    candidates;
              in
              filtered
          ) attrs;
          done = all isAttrs (attrValues result);
        in
        if done then result else reduceDependencies result;

    in
    reduceDependencies allDependencies;

  /*
    Check if a package is a local package.
    .
  */
  isLocalPackage =
    package:
    # Path to local workspace project
    package.source ? editable
    # Path to non-uv project
    || package.source ? directory
    # Path to local project with no build-system defined
    || package.source ? virtual;

  /*
    Get relative path for a local package
    .
  */
  getLocalPath =
    package:
    package.source.editable or package.source.directory or package.source.virtual
      or (throw "Not a project path: ${toJSON package.source}");

  /*
    Filter dependencies/optional-dependencies/dev-dependencies from a uv.lock package entry
    .
  */
  filterPackage =
    environ:
    let
      filterDeps = filter (dep: dep.marker == null || evalMarkers environ dep.marker);
    in
    package:
    package
    // {
      dependencies = filterDeps package.dependencies;
      optional-dependencies = mapAttrs (_: filterDeps) package.optional-dependencies;
      dev-dependencies = mapAttrs (_: filterDeps) package.dev-dependencies;
    };

  /*
    Parse unmarshaled uv.lock
    .
  */
  parseLock =
    let
      parseOptions =
        {
          resolution-mode ? null,
          exclude-newer ? null,
          prerelease-mode ? null,
        }:
        {
          inherit resolution-mode exclude-newer prerelease-mode;
        };
    in
    {
      version,
      requires-python,
      manifest ? { },
      package ? [ ],
      resolution-markers ? [ ],
      supported-markers ? [ ],
      options ? { },
    }:
    assert version == 1;
    {
      inherit version;
      requires-python = pep440.parseVersionConds requires-python;
      manifest = self.parseManifest manifest;
      package = map self.parsePackage package;
      resolution-markers = listToAttrs (
        map (markers: lib.nameValuePair markers (parseMarkers markers)) resolution-markers
      );
      supported-markers = map parseMarkers supported-markers;
      options = parseOptions options;
    };

  parseManifest =
    {
      members ? [ ],
    }:
    {
      inherit members;
    };

  /*
    Parse a package entry from uv.lock
    .
  */
  parsePackage =
    let
      parseWheel =
        {
          url,
          hash,
          size ? null,
        }:
        {
          inherit url hash size;
          file' = parseWheelFileName (baseNameOf url);
        };

      parseMetadata =
        let
          parseRequires =
            {
              name,
              marker ? null,
              url ? null,
              path ? null,
              directory ? null,
              editable ? null,
              git ? null,
              specifier ? null,
              extras ? null,
            }:
            {
              inherit
                name
                url
                path
                directory
                editable
                git
                extras
                ;
              marker = if marker != null then parseMarkers marker else null;
              specifier = if specifier != null then pep440.parseVersionCond specifier else null;
            };
        in
        {
          requires-dist ? [ ],
          requires-dev ? { },
        }:
        {
          requires-dist = map parseRequires requires-dist;
          requires-dev = mapAttrs (_: map parseRequires) requires-dev;
        };

      parseDependency =
        {
          name,
          marker ? null,
          version ? null,
          source ? { },
          extra ? [ ],
        }:
        {
          inherit
            name
            source
            version
            extra
            ;
          version' = if version != null then pep440.parseVersion version else null;
          marker = if marker != null then parseMarkers marker else null;
        };

    in
    {
      name,
      version,
      source,
      resolution-markers ? [ ],
      dependencies ? [ ],
      optional-dependencies ? { },
      dev-dependencies ? { },
      metadata ? { },
      wheels ? [ ],
      sdist ? { },
    }:
    {
      inherit
        name
        version
        source
        sdist
        ;
      version' = pep440.parseVersion version;
      wheels = map parseWheel wheels;
      metadata = parseMetadata metadata;
      # Don't parse resolution-markers.
      # All resolution-markers are also in the toplevel, meaning the string can be used as a lookup key from the top-level marker.
      inherit resolution-markers;
      dependencies = map parseDependency dependencies;

      optional-dependencies = mapAttrs (_: map parseDependency) optional-dependencies;
      dev-dependencies = mapAttrs (_: map parseDependency) dev-dependencies;
    };
})
