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
    ;
  inherit (builtins) readDir;
  inherit (pyproject-nix.lib.project) loadUVPyproject; # Note: Maybe we want a loader that will just "remap-all-the-things" into standard attributes?
  inherit (pyproject-nix.lib) pep508;
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
    mkOverlay { }

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
      # Consider: Expose as overlay instead of function wrapping mkOverlay. Not sure what is best.
      # mkOverlay could support environment customisation without weird internal overlay attributes.
      mkOverlay =
        _: final: _prev:
        let
          inherit (final) python callPackage;

          # TODO: Environment customisation
          environ = pep508.mkEnviron python;

          mkPackage = lock1.mkPackage {
            projects = workspaceProjects;
            inherit environ workspaceRoot;
          };

          resolved = lock1.resolveDependencies {
            # Note: Attrset in the shape of pep621.parseDependencies
            dependencies = {
              dependencies = topLevelDependencies;
              extras = { };
              build-systems = [ ];
            };
            lock = uvLock;
            inherit environ;
          };

        in
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
