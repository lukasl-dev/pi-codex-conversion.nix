{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  rustPlatform,
  pkg-config,
  openssl,
  alsa-lib,
  libopus,
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
  upstreamBuildTsconfig = builtins.fromJSON (builtins.readFile "${packageSrc}/tsconfig.build.json");
  buildTsconfig = upstreamBuildTsconfig // {
    compilerOptions = upstreamBuildTsconfig.compilerOptions // {
      # --noCheck still resolves explicitly requested type libraries on newer tsgo releases.
      types = [ ];
    };
  };

  # Avoid the crates.io API download endpoint, which intermittently rejects
  # GitHub-hosted Nix builders. The static CDN supports the same URL layout.
  importCargoLock = rustPlatform.importCargoLock.override {
    fetchurl =
      args:
      fetchurl (
        args
        // {
          url =
            lib.replaceString "https://crates.io/api/v1/crates" "https://static.crates.io/crates"
              args.url;
        }
      );
  };

  packageJson =
    (removeAttrs upstreamPackageJson [
      "devDependencies"
      "peerDependencies"
    ])
    // {
      scripts = (upstreamPackageJson.scripts or { }) // {
        build = "tsgo --noCheck -p tsconfig.build.json && node ../../scripts/build-extension-changelog.mjs .";
      };
    };

  tools = rustPlatform.buildRustPackage {
    pname = "pi-codex-conversion-tools";
    inherit version;

    src = "${packageSrc}/src/tools";
    cargoDeps = importCargoLock {
      lockFile = "${packageSrc}/src/tools/Cargo.lock";
    };

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];

    doCheck = false;
  };

  voice = rustPlatform.buildRustPackage {
    pname = "pi-codex-conversion-voice";
    inherit version;

    src = "${packageSrc}/src/voice/rust";
    cargoDeps = importCargoLock {
      lockFile = "${packageSrc}/src/voice/rust/Cargo.lock";
    };

    nativeBuildInputs = [ pkg-config ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      alsa-lib
      libopus
    ];

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

    cat > tsconfig.build.json <<'JSON'
    ${builtins.toJSON buildTsconfig}
    JSON

    cp ${./package-lock.json} package-lock.json
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r \
      src \
      dist \
      code-mode \
      examples \
      scripts \
      types \
      package.json \
      tsconfig.json \
      tsconfig.build.json \
      changelog.ts \
      changelog.js \
      CHANGELOG.md \
      README.md \
      UPSTREAM_SYNC.md \
      LICENSE \
      node_modules \
      $out/

    rm -rf \
      $out/src/tools/apply-patch/bin/* \
      $out/src/tools/exec/bin/* \
      $out/src/tools/view-image/bin/* \
      $out/src/voice/bin/*

    mkdir -p \
      $out/src/tools/apply-patch/bin/${platformArch} \
      $out/src/tools/exec/bin/${platformArch} \
      $out/src/tools/view-image/bin/${platformArch} \
      $out/src/voice/bin/${platformArch}

    cp ${tools}/bin/apply_patch \
      $out/src/tools/apply-patch/bin/${platformArch}/apply_patch
    cp ${tools}/bin/exec_bridge \
      $out/src/tools/exec/bin/${platformArch}/exec_bridge
    cp ${tools}/bin/view_image \
      $out/src/tools/view-image/bin/${platformArch}/view_image
    cp ${voice}/bin/pi-codex-voice \
      $out/src/voice/bin/${platformArch}/pi-codex-voice

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
