{ pyproject-nix, lib, ... }:

let
  inherit (pyproject-nix.lib.pep621) parseRequiresPython;
  inherit (pyproject-nix.lib.pep508) parseMarkers evalMarkers;
  inherit (pyproject-nix.lib.pypa) parseWheelFileName;
  inherit (pyproject-nix.lib) pep440;
  inherit (builtins) baseNameOf;
  inherit (lib) mapAttrs fix filter;

  # TODO: Consider caching resolution-markers from top-level

in

fix (self: {
  resolveDependencies =
    {
      # Project as loaded by pyproject-nix.lib.project.loadUVPyproject
      project,
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
      # Get full Python version from environment for filtering
      pythonVersion = environ.python_full_version.value;

      # Project top-level dependencies
      topLevelDependencies = dependencies.dependencies;

    in
    null;

  filterPackage =
    environ:
    let
      filterDeps = filter (dep:  dep.marker == null || evalMarkers environ dep.marker);
    in
    package:
    package // {
      dependencies = filterDeps package.dependencies;
      optional-dependencies = mapAttrs (_: filterDeps) package.optional-dependencies;
      dev-dependencies = mapAttrs (_: filterDeps) package.optional-dependencies;
    };

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
    {
      inherit version;
      requires-python = parseRequiresPython requires-python;
      manifest = self.parseManifest manifest;
      package = map self.parsePackage package;
      resolution-markers = map parseMarkers resolution-markers;
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
        }:
        {
          inherit name source version;
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
      resolution-markers = map parseMarkers resolution-markers;
      dependencies = map parseDependency dependencies;
      optional-dependencies = mapAttrs (_: map parseDependency) optional-dependencies;
      dev-dependencies = mapAttrs (_: map parseDependency) dev-dependencies;
    };
})
