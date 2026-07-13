{
  lib,
  stdenv,
  buildNpmPackage,
  rustPlatform,
  pkg-config,
  openssl,
  nodejs,
  typescript-go,
  src,
  packageSrc,
  version,
  npmDepsHash,
}:

let
  platformArch =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x64";
      aarch64-darwin = "darwin-arm64";
    }
    .${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  upstreamPackageJson = builtins.fromJSON (builtins.readFile "${packageSrc}/package.json");
  packageJson =
    (removeAttrs upstreamPackageJson [
      "devDependencies"
      "peerDependencies"
    ])
    // {
      scripts = (upstreamPackageJson.scripts or { }) // {
        build = "tsgo --noCheck -p tsconfig.build.json";
      };
    };

  tools = rustPlatform.buildRustPackage {
    pname = "pi-codex-conversion-tools";
    inherit version;

    src = "${packageSrc}/src/tools";
    cargoLock.lockFile = "${packageSrc}/src/tools/Cargo.lock";

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];

    doCheck = false;
  };
in
buildNpmPackage {
  pname = "pi-codex-conversion";
  inherit version src npmDepsHash;
  sourceRoot = "source/packages/pi-codex-conversion";

  nativeBuildInputs = [ typescript-go ];
  makeCacheWritable = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
    "--workspaces=false"
  ];

  postPatch = ''
    cat > package.json <<'JSON'
    ${builtins.toJSON packageJson}
    JSON

    cp ${./package-lock.json} package-lock.json
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r \
      src \
      dist \
      bin \
      code-mode \
      examples \
      scripts \
      package.json \
      tsconfig.json \
      tsconfig.build.json \
      available-tools.png \
      CHANGELOG.md \
      PATH_TOOLS.md \
      README.md \
      UPSTREAM_SYNC.md \
      LICENSE \
      node_modules \
      $out/

    for script in apply_patch view_image web_run imagegen; do
      substituteInPlace $out/bin/$script \
        --replace-fail "#!/usr/bin/env node" "#!${nodejs}/bin/node"
    done

    rm -rf \
      $out/src/tools/apply-patch/bin/* \
      $out/src/tools/exec/bin/* \
      $out/src/tools/view-image/bin/* \
      $out/src/tools/web-run/bin/* \
      $out/src/tools/imagegen/bin/*

    mkdir -p \
      $out/src/tools/apply-patch/bin/${platformArch} \
      $out/src/tools/exec/bin/${platformArch} \
      $out/src/tools/view-image/bin/${platformArch} \
      $out/src/tools/web-run/bin/${platformArch} \
      $out/src/tools/imagegen/bin/${platformArch}

    cp ${tools}/bin/apply_patch \
      $out/src/tools/apply-patch/bin/${platformArch}/apply_patch
    cp ${tools}/bin/exec_bridge \
      $out/src/tools/exec/bin/${platformArch}/exec_bridge
    cp ${tools}/bin/view_image \
      $out/src/tools/view-image/bin/${platformArch}/view_image
    cp ${tools}/bin/web_run \
      $out/src/tools/web-run/bin/${platformArch}/web_run
    cp ${tools}/bin/imagegen \
      $out/src/tools/imagegen/bin/${platformArch}/imagegen

    runHook postInstall
  '';

  meta = {
    description = "Codex-oriented tool and prompt adapter for pi coding agent";
    homepage = "https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
