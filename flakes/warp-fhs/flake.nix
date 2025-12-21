{
  description = "Warp Terminal with FHS environment for full system access";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      packages.${system} = {
        default = pkgs.buildFHSEnv {
          name = "warp-terminal";

          targetPkgs = pkgs: with pkgs; [
            # Core Warp package
            warp-terminal

            # Shells
            bash
            zsh
            fish
            nushell

            # Core utilities that Warp needs
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            util-linux

            # System tools
            sudo
            shadow # for su and other user management
            procps
            psmisc

            # Development tools
            git
            openssh
            curl
            wget

            # SSL/TLS certificates
            cacert
            openssl

            # Terminal utilities
            ncurses
            less
            man
            which
            file
            tree

            # For proper terminal operation
            glibc
            gcc
            binutils

            # Locale support
            glibcLocales
          ];

          # Additional packages that might be needed
          multiPkgs = pkgs: with pkgs; [
            # Add 32-bit support if needed
          ];

          runScript = "warp-terminal";

          profile = ''
            # Preserve user's HOME
            export HOME=/home/kosta

            # Set up SSL certificates
            export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt

            # Set up locale
            export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive

            # Ensure proper PATH includes FHS directories
            export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH

            # Preserve important environment variables
            # NIX_* variables will be inherited automatically

            # Set up user profile if it exists
            if [ -f "$HOME/.profile" ]; then
              source "$HOME/.profile"
            fi

            # Source bashrc if using bash
            if [ -f "$HOME/.bashrc" ] && [ -n "$BASH_VERSION" ]; then
              source "$HOME/.bashrc"
            fi
          '';

          extraInstallCommands = ''
            # Copy desktop entry and icons from the original package
            mkdir -p $out/share/applications
            mkdir -p $out/share/pixmaps
            mkdir -p $out/share/icons

            if [ -d ${pkgs.warp-terminal}/share/applications ]; then
              cp -r ${pkgs.warp-terminal}/share/applications/* $out/share/applications/
            fi

            if [ -d ${pkgs.warp-terminal}/share/pixmaps ]; then
              cp -r ${pkgs.warp-terminal}/share/pixmaps/* $out/share/pixmaps/
            fi

            if [ -d ${pkgs.warp-terminal}/share/icons ]; then
              cp -r ${pkgs.warp-terminal}/share/icons/* $out/share/icons/
            fi
          '';
        };

        warp-fhs = self.packages.${system}.default;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/warp-terminal";
        };
        warp-terminal = self.apps.${system}.default;
      };
    };
}
