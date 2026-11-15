{ inputs, ... }:
{
  nixos.modules.workstation =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      cfg = config.programs.codex;

      # Import from llm-agents.nix
      inherit (inputs) llm-agents;
      codex-pkg = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
    in
    {
      options.programs.codex = {
        enable = lib.mkEnableOption "OpenAI Codex CLI";

        package = lib.mkOption {
          type = lib.types.package;
          default = codex-pkg;
          description = "The Codex package to use";
        };
      };

      config = lib.mkIf cfg.enable {
        # Add codex to system packages
        environment.systemPackages = [
          cfg.package
        ];
      };
    };
}
