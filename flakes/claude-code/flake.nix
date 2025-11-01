{
  description = "Anthropic Claude Code CLI - Latest from npm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          default = self.packages.${system}.claude-code;
          claude-code = pkgs.buildNpmPackage rec {
            pname = "claude-code";
            version = "2.0.31";

            nodejs = pkgs.nodejs_20; # required for sandboxed Nix builds on Darwin

            src = pkgs.fetchzip {
              url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
              hash = "sha256-KQRc9h2DG1bwWvMR1EnMWi9qygPF0Fsr97+TyKef3NI=";
            };

            npmDepsHash = "sha256-x1Wm/cpXKljD3X8TT+1xJrMixkEzPJg7D2ioUsjAI5I=";

            postPatch = ''
              cp ${./package-lock.json} package-lock.json
            '';

            dontNpmBuild = true;

            AUTHORIZED = "1";

            # `claude-code` tries to auto-update by default, this disables that functionality.
            # https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview#environment-variables
            # The DEV=true env var causes claude to crash with `TypeError: window.WebSocket is not a constructor`
            postInstall = ''
              wrapProgram $out/bin/claude \
                --set DISABLE_AUTOUPDATER 1 \
                --unset DEV
            '';

            passthru.updateScript = ./update.sh;

            meta = with pkgs.lib; {
              description = "An agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
              homepage = "https://github.com/anthropics/claude-code";
              downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
              license = licenses.unfree;
              maintainers = [ ];
              platforms = platforms.linux;
              mainProgram = "claude";
            };
          };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/claude";
        };
      });
    };
}
