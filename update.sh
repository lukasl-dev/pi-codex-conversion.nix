#!/usr/bin/env -S nix shell .#update-script-env -c bash
# shellcheck shell=bash
set -euo pipefail

owner=IgorWarzocha
repo_name=howaboua-pi-stuff
branch=main
api_commits_url="https://api.github.com/repos/${owner}/${repo_name}/commits"
archive_base_url="https://github.com/${owner}/${repo_name}/archive"
package_dir=packages/pi-codex-conversion
version_file=version.json
package_lock_file=package-lock.json

die() {
	echo "$*" >&2
	exit 1
}
out() { [[ -n ${GITHUB_OUTPUT:-} ]] && echo "$1=$2" >>"$GITHUB_OUTPUT" || true; }

set_if_changed() {
	local var=$1 backup=$2 cur=$3
	if [[ ! -f "$backup" ]] || ! cmp -s "$cur" "$backup"; then
		printf -v "$var" true
	else
		printf -v "$var" false
	fi
}

latest_package_rev() {
	curl -fsSL \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"${api_commits_url}?sha=${branch}&path=${package_dir}&per_page=1" |
		jq -r '.[0].sha // empty'
}

write_version_json() {
	local version=$1 rev=$2 hash=$3 npm_deps_hash=$4 tmp
	tmp=$(mktemp)
	jq \
		--arg version "$version" \
		--arg rev "$rev" \
		--arg hash "$hash" \
		--arg npmDepsHash "$npm_deps_hash" \
		'.version = $version
    | .rev = $rev
    | .hash = $hash
    | .npmDepsHash = $npmDepsHash' \
		"$version_file" >"$tmp"
	mv "$tmp" "$version_file"
}

validate_package_lock() {
	local lockfile=$1 missing
	missing=$(jq -r '
    .packages
    | to_entries[]
    | select(.key | contains("node_modules/"))
    | select((.value.link // false) | not)
    | select(((.value | has("resolved")) | not) or ((.value | has("integrity")) | not))
    | .key
  ' "$lockfile")

	if [[ -n "$missing" ]]; then
		echo "package-lock.json still has incomplete package entries:" >&2
		echo "$missing" >&2
		exit 1
	fi
}

cleanup() {
	rm -rf "$tmpdir" "$backup_dir"
}

restore_file() {
	local path=$1
	if [[ -f "$backup_dir/$path" ]]; then
		cp "$backup_dir/$path" "$path" 2>/dev/null || true
	else
		rm -f "$path"
		if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			git reset -q -- "$path" 2>/dev/null || true
		fi
	fi
}

restore_and_cleanup() {
	local status=$?
	if ((status != 0)); then
		restore_file "$version_file"
		restore_file "$package_lock_file"
	fi
	cleanup
	exit "$status"
}

current_rev=$(jq -r '.rev' "$version_file")
current_version=$(jq -r '.version' "$version_file")
latest_rev=$(latest_package_rev)
[[ -n "$latest_rev" ]] || die "Failed to determine latest upstream commit touching ${package_dir}"

tmpdir=$(mktemp -d)
backup_dir=$(mktemp -d)
for path in "$version_file" "$package_lock_file"; do
	[[ -f "$path" ]] && cp "$path" "$backup_dir/$path"
done
trap restore_and_cleanup EXIT

archive_url="${archive_base_url}/${latest_rev}.tar.gz"
prefetch_json=$(nix store prefetch-file --json --unpack "$archive_url")
read -r src_hash src_path < <(jq -r '[.hash, .storePath] | @tsv' <<<"$prefetch_json")

cp -R "$src_path"/. "$tmpdir"/
chmod -R u+w "$tmpdir"

upstream_package_json="$tmpdir/$package_dir/package.json"
[[ -f "$upstream_package_json" ]] || die "Upstream archive does not contain ${package_dir}/package.json"

target_version=$(jq -r '.version' "$upstream_package_json")
[[ -n "$target_version" && "$target_version" != "null" ]] || die "Failed to read upstream package version"

package_tmp="$tmpdir/package"
mkdir -p "$package_tmp"
cp -R "$tmpdir/$package_dir"/. "$package_tmp"/

pushd "$package_tmp" >/dev/null
jq 'del(.devDependencies, .peerDependencies)' package.json >package.json.tmp
mv package.json.tmp package.json
npm install --package-lock-only --omit=dev --legacy-peer-deps --ignore-scripts
validate_package_lock package-lock.json
cp package-lock.json "$OLDPWD/$package_lock_file"
popd >/dev/null

package_lock_changed=false
set_if_changed package_lock_changed "$backup_dir/$package_lock_file" "$package_lock_file"

rev_changed=false
[[ "$latest_rev" != "$current_rev" ]] && rev_changed=true
version_changed=false
[[ "$target_version" != "$current_version" ]] && version_changed=true

if [[ "$rev_changed" == true || "$package_lock_changed" == true ]]; then
	npm_deps_hash=$(prefetch-npm-deps "$package_lock_file" | tail -n1)
	[[ -n "$npm_deps_hash" ]] || die "Failed to determine npmDepsHash"
	write_version_json "$target_version" "$latest_rev" "$src_hash" "$npm_deps_hash"
fi

version_json_changed=false
set_if_changed version_json_changed "$backup_dir/$version_file" "$version_file"

# Nix flakes ignore untracked files. Mark newly generated files as intent-to-add
# so local flake builds can see them before the final workflow commit step.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git add --intent-to-add -- "$version_file" "$package_lock_file"
fi

if [[ "$version_json_changed" == true || "$package_lock_changed" == true ]]; then
	nix build . --no-link >/dev/null
fi

if [[ "$rev_changed" == true ]]; then
	echo "Updated pi-codex-conversion to ${target_version} (${latest_rev:0:12})"
elif [[ "$package_lock_changed" == true ]]; then
	echo "Updated package-lock.json for ${target_version}"
else
	echo "version.json already points to ${current_rev}"
	echo "No changes to commit"
fi

out version "$target_version"
out rev "$latest_rev"
out short_rev "${latest_rev:0:12}"
out rev_changed "$rev_changed"
out version_changed "$version_changed"
out package_lock_changed "$package_lock_changed"
out version_json_changed "$version_json_changed"

trap - EXIT
cleanup
