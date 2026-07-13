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

          update-script-env = pkgs.symlinkJoin {
            name = "pi-codex-conversion-update-script-env";
            paths = [
              pkgs.bash
              pkgs.curl
              pkgs.git
              pkgs.jq
              pkgs.nix
              pkgs.nodejs
              pkgs.prefetch-npm-deps
            ];
          };
        }
      );

      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt-rfc-style
      );
    };
}
