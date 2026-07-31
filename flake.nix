{
  description = "pi-codex-conversion";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      nixpkgs,
      systems,
      ...
    }:
    let
      current = builtins.fromJSON (builtins.readFile ./version.json);
      inherit (current)
        version
        rev
        hash
        npmDepsHash
        ;

      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          monorepoSrc = pkgs.fetchFromGitHub {
            owner = "IgorWarzocha";
            repo = "howaboua-pi-stuff";
            inherit rev hash;
          };
          packageSrc = "${monorepoSrc}/packages/pi-codex-conversion";
        in
        rec {
          default = pi-codex-conversion;

          pi-codex-conversion = pkgs.callPackage ./package.nix {
            src = monorepoSrc;
            inherit packageSrc version npmDepsHash;
          };
        }
      );

      apps = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          syncUpstream = import ./sync-upstream.nix { inherit pkgs; };
          update = import ./update.nix {
            inherit pkgs syncUpstream;
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/pi-codex-conversion-update";
            meta.description = "Update pi-codex-conversion to the latest npm release";
          };
          sync-upstream = {
            type = "app";
            program = "${syncUpstream}/bin/pi-codex-conversion-sync-upstream";
            meta.description = "Synchronize pi-codex-conversion with its latest npm release";
          };
        }
      );

      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt
      );
    };
}
