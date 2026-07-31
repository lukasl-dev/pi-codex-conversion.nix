# pi-codex-conversion.nix

A Nix flake for [pi-codex-conversion](https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion), a Codex-oriented tool and prompt adapter for the [pi](https://github.com/earendil-works/pi) coding agent.

It provides:

- a `pi-codex-conversion` package built from the upstream npm package plus its Rust tool binaries
- a daily scheduled workflow that bumps `version.json` and `package-lock.json` when upstream changes
- `update` and `sync-upstream` flake apps for updating to the latest npm release

> [!IMPORTANT]
> This is not the official packaging for pi-codex-conversion. It vendors the upstream source via `fetchFromGitHub` and rebuilds the Rust tools with `buildRustPackage`.

## Updating

Update the package metadata and npm lockfile with:

```sh
nix run .#update
```

The lower-level synchronization app can be run directly with:

```sh
nix run .#sync-upstream
```

## Using with [pi.nix](https://github.com/lukasl-dev/pi.nix)

Add both flakes as inputs:

```nix
{
  inputs = {
    pi.url = "github:lukasl-dev/pi.nix";
    pi-codex-conversion.url = "github:lukasl-dev/pi-codex-conversion.nix";
  };
}
```

Then point `programs.pi.coding-agent.extensions` at the pi-codex-conversion
package:

```nix
{ inputs, pkgs, config, ... }:
let
  inherit (inputs.pi-codex-conversion.packages.${pkgs.system}) pi-codex-conversion;
in
{
  imports = [ inputs.pi.nixosModules.default ];

  programs.pi.coding-agent = {
    enable = true;

    # Load the extension from the Nix store. Its bundled Rust tools and
    # bin/ wrappers are resolved relative to this path.
    extensions = [ "${pi-codex-conversion}" ];
  };
}
```
