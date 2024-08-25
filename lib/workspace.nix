{
  lib,
  pyproject-nix,
  lock1,
  ...
}:

let
  inherit (lib)
    importTOML
    splitString
    length
    elemAt
    filter
    attrsToList
    match
    replaceStrings
    concatMap
    optional
    any
    fix
    groupBy
    mapAttrs
    optionalAttrs
    head
    attrNames
    all
    ;
  inherit (builtins) readDir;
  inherit (pyproject-nix.lib.project) loadUVPyproject; # Note: Maybe we want a loader that will just "remap-all-the-things" into standard attributes?
  inherit (pyproject-nix.lib) pep440 pep508;
  inherit (pyproject-nix.lib) pypa;

  # Match str against a glob pattern
  globMatches =
    let
      mkRe = replaceStrings [ "*" ] [ ".*" ]; # Make regex from glob pattern
    in
    glob:
    let
      re = mkRe glob;
    in
    s: match re s != null;

  splitPath = splitString "/";

in

fix (self: {
  /*
    Load a workspace from a workspace root.

    Returns an attribute set where you can call:
    mkOverlay { sourcePreference = "wheel"; } # wheel or sdist

    to create a Nixpkgs Python packageOverrides overlay
  */
  loadWorkspace =
    { workspaceRoot }:
    let
      pyproject = importTOML (workspaceRoot + "/pyproject.toml");
      uvLock = lock1.parseLock (importTOML (workspaceRoot + "/uv.lock"));

      members = self.discoverWorkspace { inherit workspaceRoot pyproject; };

      # Map package names to pyproject.nix projects
      workspaceProjects =
        mapAttrs
          (
            _: project:
            assert length project == 1;
            head project
          )
          (
            groupBy (project: pypa.normalizePackageName project.pyproject.project.name) (
              map (
                relPath:
                loadUVPyproject { projectRoot = workspaceRoot + "${relPath}"; }
                # We've already loaded this file for workspace discovery, just bung it in.
                // optionalAttrs (relPath == "/") { inherit pyproject; }
              ) members
            )
          );

      # Bootstrap resolver from top-level workspace projects
      topLevelDependencies = map pep508.parseString (attrNames workspaceProjects);

    in
    {
      /*
        Generate a Nixpkgs Python overlay from uv workspace.

        See https://nixos.org/manual/nixpkgs/stable/#overriding-python-packages
      */
      mkOverlay =
        {
          # Whether to prefer sources from either:
          # - wheel
          # - sdist
          #
          # See FAQ for more information.
          sourcePreference,
          # PEP-508 environment customisations.
          # Example: { platform_release = "5.10.65"; }
          environ ? { },
        }:
        final: prev:
        let
          inherit (final) callPackage;

          # Note: Using Python from final here causes infinite recursion.
          # There is no correct way to override the python interpreter from within the set anyway,
          # so all facts that we get from the interpreter derivation are still the same.
          environ' = pep508.setEnviron (pep508.mkEnviron prev.python) environ;
          pythonVersion = environ'.python_full_version.value;

          mkPackage = lock1.mkPackage {
            projects = workspaceProjects;
            environ = environ';
            inherit workspaceRoot sourcePreference;
          };

          resolved = lock1.resolveDependencies {
            # Note: Attrset in the shape of pep621.parseDependencies
            dependencies = {
              dependencies = topLevelDependencies;
              extras = { };
              build-systems = [ ];
            };
            lock = uvLock;
            environ = environ';
          };

        in
        # Assert that requires-python from uv.lock is compatible with this interpreter
        assert all (spec: pep440.comparators.${spec.op} pythonVersion spec.version) uvLock.requires-python;
        mapAttrs (_: pkg: callPackage (mkPackage pkg) { }) resolved;

      inherit topLevelDependencies;
    };

  /*
    Discover workspace member directories from a workspace root.
    Returns a list of strings relative to the workspace root.
  */
  discoverWorkspace =
    {
      # Workspace root directory
      workspaceRoot,
      # Workspace top-level pyproject.toml
      pyproject ? importTOML (workspaceRoot + "/pyproject.toml"),
    }:
    let
      workspace' = pyproject.tool.uv.workspace or { };
      excluded = map (g: globMatches "/${g}") (workspace'.exclude or [ ]);
      globs = map splitPath (workspace'.members or [ ]);

    in
    # Get a list of workspace member directories
    filter (x: length excluded == 0 || any (e: !e x) excluded) (
      concatMap (
        glob:
        let
          max = (length glob) - 1;
          recurse =
            rel: i:
            let
              dir = workspaceRoot + "/${rel}";
              dirs = map (e: e.name) (filter (e: e.value == "directory") (attrsToList (readDir dir)));
              matches = filter (globMatches (elemAt glob i)) dirs;
            in
            if i == max then
              map (child: rel + "/${child}") matches
            else
              concatMap (child: recurse (rel + "/${child}") (i + 1)) matches;
        in
        recurse "" 0
      ) globs
    )
    # If the package is a virtual root we don't add the workspace root to project discovery
    ++ optional (pyproject ? project) "/";

})
