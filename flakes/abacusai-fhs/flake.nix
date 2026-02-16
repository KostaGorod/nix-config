{
  description = "AbacusAI DeepAgent Desktop and CLI";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      version = "1.106.25007";

      guiSrc = pkgs.fetchurl {
        url = "https://github.com/abacusai/deepagent-releases/releases/download/${version}/AbacusAI-linux-x64-${version}.tar.gz";
        sha256 = "e28913fd611e825261f6038a1941cb8c665af15c247bca62dbbd146b5a54c40d";
      };

      cliSrc = pkgs.fetchurl {
        url = "https://github.com/abacusai/deepagent-releases/releases/download/${version}/abacusai-agent-cli-linux-x64-${version}.tar.gz";
        sha256 = "b91ce323d2d23cb706cd923285e716747ca7b1bcd92f48eb98bea8dcf52bb72c";
      };

      commonDeps = with pkgs; [
        stdenv.cc.cc.lib
        glib
        gtk3
        nss
        nspr
        libdrm
        mesa
        libGL
        libglvnd
        libxkbcommon
        libsecret
        libpulseaudio
        alsa-lib
        dbus
        libnotify
        at-spi2-atk
        at-spi2-core
        atk
        cairo
        cups
        expat
        fontconfig
        freetype
        gdk-pixbuf
        pango
        zlib
        xorg.libX11
        xorg.libXcursor
        xorg.libXrandr
        xorg.libXdamage
        xorg.libXfixes
        xorg.libXi
        xorg.libXcomposite
        xorg.libXrender
        xorg.libXtst
        xorg.libXScrnSaver
        xorg.libXext
        xorg.libxkbfile
        xorg.libxcb
      ];

      abacusai-gui = pkgs.stdenv.mkDerivation {
        pname = "abacusai-gui";
        inherit version;
        src = guiSrc;

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = commonDeps;

        # Ignore musl binaries (Alpine Linux prebuilds that won't work on NixOS)
        autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          mkdir -p $out/opt/abacusai
          cp -r ./* $out/opt/abacusai/
          mkdir -p $out/bin
          ln -s $out/opt/abacusai/abacusai-app $out/bin/abacusai-app
          # Also expose embedded CLI
          ln -s $out/opt/abacusai/bin/abacusai $out/bin/abacusai-embedded
          runHook postInstall
        '';
      };

      abacusai-cli = pkgs.stdenv.mkDerivation {
        pname = "abacusai-cli";
        inherit version;
        src = cliSrc;

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = commonDeps;

        # Ignore musl binaries
        autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          mkdir -p $out/opt/abacusai-cli
          cp -r ./* $out/opt/abacusai-cli/
          mkdir -p $out/bin
          ln -s $out/opt/abacusai-cli/bin/abacusai $out/bin/abacusai
          runHook postInstall
        '';
      };

      abacusai-fhs = pkgs.buildFHSEnv {
        name = "abacusai";
        targetPkgs =
          pkgs:
          commonDeps
          ++ [
            # Ensure the bundled CLI can run inside the GUI FHS env too.
            pkgs.nodejs_20
            abacusai-gui
            abacusai-cli
            pkgs.openssh
            pkgs.git
          ];
        runScript = "abacusai-app";

        extraInstallCommands = ''
                    mkdir -p $out/share/applications
                    cat > $out/share/applications/abacusai.desktop <<EOF
          [Desktop Entry]
          Type=Application
          Name=AbacusAI
          Comment=Abacus.AI DeepAgent desktop client
          Exec=abacusai %U
          Terminal=false
          Categories=Development;IDE;
          EOF
        '';
      };

      abacusai-cli-fhs = pkgs.buildFHSEnv {
        name = "abacusai-cli";
        targetPkgs =
          pkgs:
          commonDeps
          ++ [
            # The upstream CLI launcher is a Node script and expects `node` on PATH.
            pkgs.nodejs_20
            abacusai-cli
            pkgs.openssh
            pkgs.git
          ];
        # Be explicit about which `abacusai` we execute.
        # If the host has some other `/usr/bin/abacusai` installed, a plain
        # `runScript = "abacusai"` can accidentally pick that up.
        runScript = "${abacusai-cli}/bin/abacusai";
      };

    in
    {
      packages.${system} = {
        default = self.packages.${system}.gui;
        gui = abacusai-fhs;
        cli = abacusai-cli-fhs;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${self.packages.${system}.gui}/bin/abacusai";
        };
        cli = {
          type = "app";
          program = "${self.packages.${system}.cli}/bin/abacusai-cli";
        };
      };
    };
}
