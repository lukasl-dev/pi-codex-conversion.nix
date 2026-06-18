# pi-codex-conversion.nix

A Nix flake for [pi-codex-conversion](https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion), a Codex-oriented tool and prompt adapter for the [pi](https://github.com/earendil-works/pi) coding agent.

It provides:

- a `pi-codex-conversion` package built from the upstream npm package plus its Rust tool binaries
- a daily scheduled workflow that bumps `version.json` and `package-lock.json` when upstream changes

> [!IMPORTANT]
> This is not the official packaging for pi-codex-conversion. It vendors the upstream source via `fetchFromGitHub` and rebuilds the Rust tools with `buildRustPackage`.

## Quick start

```bash
nix run github:lukasl-dev/pi-codex-conversion.nix
```

Or build it locally:

```bash
nix build .#pi-codex-conversion
```

## Usage

```nix
{
  inputs.pi-codex-conversion.url = "github:lukasl-dev/pi-codex-conversion.nix";
}
```

### As a package

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.pi-codex-conversion.packages.${pkgs.system}.pi-codex-conversion
  ];
}
```
