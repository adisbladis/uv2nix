{ lib, pyproject-nix, ... }:
let
  inherit (lib)
    intersectLists
    length
    head
    elem
    concatMap
    assertMsg
    match
    elemAt
    listToAttrs
    splitString
    nameValuePair
    optionalAttrs
    versionAtLeast
    findFirst
    optionals
    unique
    hasPrefix
    mapAttrs
    groupBy
    ;
  inherit (pyproject-nix.lib) pypa;
  inherit (builtins) toJSON nixVersion;

  parseGitURL =
    url:
    let
      # No query params
      m1 = match "([^#]+)#(.+)" url;

      # With query params
      m2 = match "([^?]+)\\?([^#]+)#(.+)" url;
    in
    if m1 != null then
      {
        url = elemAt m1 0;
        query = { };
        fragment = elemAt m1 1;
      }
    else if m2 != null then
      {
        url = elemAt m2 0;
        query = listToAttrs (
          map (
            s:
            let
              parts = splitString "=" s;
            in
            assert length parts == 2;
            nameValuePair (elemAt parts 0) (elemAt parts 1)
          ) (splitString "&" (elemAt m2 1))
        );
        fragment = elemAt m2 2;
      }
    else
      throw "Could not parse git url: ${url}";

in
{
  /*
    Create a function returning an intermediate attributes set shared between builder implementations
    .
  */
  mkRenderIntermediate =
    { config, workspaceRoot }:
    let
      inherit (config)
        no-binary
        no-build
        no-binary-package
        no-build-package
        ;
      unbuildable-packages = intersectLists no-binary-package no-build-package;
    in
    package:
    let

      # Wheels grouped by filename
      wheels = mapAttrs (
        _: whl:
        assert length whl == 1;
        head whl
      ) (groupBy (whl: whl.file'.filename) package.wheels);
      # List of parsed wheels
      wheelFiles = map (whl: whl.file') package.wheels;

    in
    {
      stdenv,
      python,
      sourcePreference,
      fetchurl,
      autoPatchelfHook,
      pythonManylinuxPackages,
    }:
    let
      inherit (package) source;
      isGit = source ? git;
      isPypi = source ? registry; # From pypi registry
      isURL = source ? url;
      isPath = source ? path; # Path to sdist

      preferWheel =
        if no-build != null && no-build then
          true
        else if no-binary != null && no-binary then
          false
        else if elem package.name no-binary-package then
          false
        else if elem package.name no-build-package then
          true
        else if sourcePreference == "sdist" then
          false
        else if sourcePreference == "wheel" then
          true
        else
          throw "Unknown sourcePreference: ${sourcePreference}";

      compatibleWheels = pypa.selectWheels stdenv.targetPlatform python wheelFiles;
      selectedWheel' = head compatibleWheels;
      selectedWheel = wheels.${selectedWheel'.filename};

      format =
        if isURL then
          (
            # Package is sdist if the source file is present in the sdist attrset
            if (source.url == package.sdist.url or null) then "pyproject" else "wheel"
          )
        else if isPypi then
          (
            if preferWheel && compatibleWheels != [ ] then
              "wheel"
            else if package.sdist == { } then
              assert assertMsg (
                compatibleWheels != [ ]
              ) "No compatible wheel, nor sdist found for package '${package.name}' ${package.version}";
              "wheel"
            else
              "pyproject"
          )
        else
          "pyproject";

    in
    # make sure there is no intersection between no-binary-packages and no-build-packages for current package
    assert assertMsg (!elem package.name unbuildable-packages) (
      "There is an overlap between packages specified as no-build and no-binary-package in the workspace. That leaves no way to build these packages: "
      + (toString unbuildable-packages)
    );
    assert assertMsg (
      format == "wheel" -> no-binary != null -> !no-binary
    ) "Package source for '${package.name}' was derived as sdist, in tool.uv.no-binary is set to true";
    assert assertMsg (
      format == "sdist" -> no-build != null -> !no-build
    ) "Package source for '${package.name}' was derived as sdist, in tool.uv.no-build is set to true";
    assert assertMsg (format == "pyproject" -> !elem package.name no-build-package)
      "Package source for '${package.name}' was derived as sdist, but was present in tool.uv.no-build-package";
    assert assertMsg (format == "wheel" -> !elem package.name no-binary-package)
      "Package source for '${package.name}' was derived as wheel, but was present in tool.uv.no-binary-package";
    (
      {
        pname = package.name;
        inherit (package) version;

        passthru = {
          inherit package format;
        };

        src =
          if isGit then
            (
              let
                parsed = parseGitURL source.git;
              in
              fetchGit (
                {
                  inherit (parsed) url;
                  rev = parsed.fragment;
                }
                // optionalAttrs (parsed ? query.tag) { ref = "refs/tags/${parsed.query.tag}"; }
                // optionalAttrs (versionAtLeast nixVersion "2.4") {
                  allRefs = true;
                  submodules = true;
                }
              )
            )
          else if isPath then
            {
              outPath = "${workspaceRoot + "/${source.path}"}";
              passthru.url = source.path;
            }
          else if (isPypi || isURL) && format == "pyproject" then
            fetchurl { inherit (package.sdist) url hash; }
          else if isURL && format == "wheel" then
            fetchurl {
              inherit
                (findFirst (
                  whl: whl.url == source.url
                ) (throw "Wheel URL ${source.url} not found in list of wheels: ${package.wheels}") package.wheels)
                url
                hash
                ;
            }
          else if format == "wheel" then
            fetchurl { inherit (selectedWheel) url hash; }
          else
            throw "Unhandled state: could not derive src for package '${package.name}' from: ${toJSON source}";
      }
      // optionalAttrs (format == "pyproject") { pyproject = true; }
      // optionalAttrs (format != "pyproject") { inherit format; }
      // optionalAttrs (format == "wheel") {
        # Don't strip prebuilt wheels
        dontStrip = true;

        # Add wheel utils
        nativeBuildInputs = lib.optional stdenv.isLinux autoPatchelfHook;
        buildInputs =
          # Add manylinux platform dependencies.
          optionals (stdenv.isLinux && stdenv.hostPlatform.libc == "glibc") (
            unique (
              concatMap (
                tag:
                (
                  if hasPrefix "manylinux1" tag then
                    pythonManylinuxPackages.manylinux1
                  else if hasPrefix "manylinux2010" tag then
                    pythonManylinuxPackages.manylinux2010
                  else if hasPrefix "manylinux2014" tag then
                    pythonManylinuxPackages.manylinux2014
                  else if hasPrefix "manylinux_" tag then
                    pythonManylinuxPackages.manylinux2014
                  else
                    [ ] # Any other type of wheel don't need manylinux inputs
                )
              ) selectedWheel'.platformTags
            )
          );
      }
    );
}
