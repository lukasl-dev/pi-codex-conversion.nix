{
  pkgs,
  syncUpstream,
}:

pkgs.writeShellApplication {
  name = "pi-codex-conversion-update";
  runtimeInputs = [ syncUpstream ];
  text = # bash
    ''
      set -euo pipefail

      pi-codex-conversion-sync-upstream
    '';
}
