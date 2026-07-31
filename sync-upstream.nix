{ pkgs }:

pkgs.writeShellApplication {
  name = "pi-codex-conversion-sync-upstream";
  runtimeInputs = with pkgs; [
    coreutils
    jq
    nix
    nodejs
    prefetch-npm-deps
  ];
  text = # bash
    ''
      set -euo pipefail

      package_name=@howaboua/pi-codex-conversion
      repository=IgorWarzocha/howaboua-pi-stuff
      package_dir=packages/pi-codex-conversion

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      metadata=$(npm view "$package_name" version gitHead --json)
      version=$(jq -r '.version // empty' <<< "$metadata")
      rev=$(jq -r '.gitHead // empty' <<< "$metadata")
      [[ -n "$version" ]] || {
        echo "Failed to determine the latest npm version of $package_name" >&2
        exit 1
      }
      [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || {
        echo "The npm release $package_name@$version has no valid gitHead" >&2
        exit 1
      }

      source=$(nix store prefetch-file --json --unpack \
        "https://github.com/$repository/archive/$rev.tar.gz")
      hash=$(jq -r .hash <<< "$source")
      src=$(jq -r .storePath <<< "$source")

      upstream_package="$src/$package_dir"
      [[ -f "$upstream_package/package.json" ]] || {
        echo "The release source does not contain $package_dir/package.json" >&2
        exit 1
      }

      source_version=$(jq -r .version "$upstream_package/package.json")
      [[ "$source_version" == "$version" ]] || {
        echo "npm reports $version, but its gitHead contains $source_version" >&2
        exit 1
      }

      cp -R "$upstream_package" "$tmpdir/package"
      chmod -R u+w "$tmpdir/package"

      pushd "$tmpdir/package" >/dev/null
      jq 'del(.devDependencies, .peerDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      npm install \
        --package-lock-only \
        --omit=dev \
        --legacy-peer-deps \
        --ignore-scripts \
        --workspaces=false

      missing=$(jq -r '
        .packages
        | to_entries[]
        | select(.key | contains("node_modules/"))
        | select((.value.link // false) | not)
        | select(((.value | has("resolved")) | not) or ((.value | has("integrity")) | not))
        | .key
      ' package-lock.json)
      if [[ -n "$missing" ]]; then
        echo "package-lock.json has incomplete package entries:" >&2
        echo "$missing" >&2
        exit 1
      fi
      popd >/dev/null

      npm_deps_hash=$(prefetch-npm-deps "$tmpdir/package/package-lock.json" | tail -n1)
      [[ -n "$npm_deps_hash" ]] || {
        echo "Failed to determine npmDepsHash" >&2
        exit 1
      }

      jq \
        --arg version "$version" \
        --arg rev "$rev" \
        --arg hash "$hash" \
        --arg npmDepsHash "$npm_deps_hash" \
        '.version = $version
          | .rev = $rev
          | .hash = $hash
          | .npmDepsHash = $npmDepsHash' \
        version.json > "$tmpdir/version.json"

      cp "$tmpdir/package/package-lock.json" package-lock.json
      cp "$tmpdir/version.json" version.json
      echo "Updated pi-codex-conversion to $version (''${rev:0:12})"
    '';
}
