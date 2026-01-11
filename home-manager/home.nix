{ config, pkgs, lib, specialArgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  inherit (specialArgs) hostname role;
  inherit (pkgs.stdenv) isLinux isDarwin;
  homeDir = if isDarwin then "/Users/" else "/home/";
  username = "kosta";
in
{


  # TODO please change the username & home directory to your own
  # home.username = "kosta";
  # home.homeDirectory = "/home/kosta";
  # home.homeDirectory = homeDir+username;
  home = {
  homeDirectory = homeDir+username;
  inherit username;
  };




  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {

  #   "Xcursor.size" = 16;
  #   "Xft.dpi" = 172;
  # };
  # Packages that should be installed to the user profile.

  home.packages = with pkgs; [
    # here is some command line tools I use frequently
    # feel free to add your own or remove some of them

    # IDE
    # pkgs-unstable.zed-editor  # disabled

    fastfetch
    nnn # terminal file manager




    # git
    git-credential-oauth

    # knowledge base tools
    obsidian
    todoist-electron
    # networking tools
    # mtr # A network diagnostic tool

    # aria2 # A lightweight multi-protocol & multi-source command-line download utility
    # socat # replacement of openbsd-netcat
    # nmap # A utility for network discovery and security auditing

    # misc #
    # cowsay

    # gnused
    # gnutar
    # gawk
    # zstd
    # gnupg

    # nix related
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    # productivity
    glow # markdown previewer in terminal
    pkgs-unstable.openterface-qt # GUI for openterface KVM


    # k8s and stuff
    kubectl
    k9s
    lens # GUI for k8s


    ##
    discord
    slack

    ## arrr
    deluge-gtk

    ##media
    kdePackages.dragon

    ## browsers
    inputs.zen-browser.packages."x86_64-linux".default # beta
    # inputs.zen-browser.packages."${system}".default # beta
  ];

  programs.vscode = {
    package = pkgs-unstable.vscode.fhs; # Use FHS version for better npm/npx support
    enable = true;
    profiles.default = {
      userSettings = {
        "window.titleBarStyle" = "custom"; # Use Vscode's TitleBarStyle instead of ugly wayland's
        "workbench.colorTheme" = "Tokyo Night Storm"; #apply theme
      };
      extensions = with pkgs-unstable; [
        # theme
        vscode-extensions.enkia.tokyo-night
        # remote-ssh
        vscode-extensions.ms-vscode-remote.remote-ssh
        vscode-extensions.ms-vscode-remote.remote-ssh-edit # complemintery to remote-ssh extention
        #copilot
        vscode-extensions.github.copilot
        vscode-extensions.github.copilot-chat

        # langauge specific
        # Nix
        vscode-extensions.bbenoist.nix # #nix highlight
        # Python
        vscode-extensions.ms-python.python
        vscode-extensions.ms-python.debugpy # Debug tool
        vscode-extensions.ms-python.vscode-pylance
        vscode-extensions.ms-pyright.pyright
        vscode-extensions.ms-python.black-formatter # Black Formatter
      ];
    };

  };

  # Git with oauth , using kwalletmanager to store the oauth token
  programs.git = {
    package = pkgs.gitFull;
    enable = true;
    settings = {
      user.name = "Kosta Gorod";
      user.email = "korolx147@gmail.com";
      credential.helper = lib.mkBefore [ "${pkgs.gitFull.override { withLibsecret = true; }}/bin/git-credential-libsecret" ];
    };
  };
  programs.git-credential-oauth.enable = true;

  # GitHub CLI - uses git's credential helper for auth
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  # # starship - an customizable prompt for any shell
  programs.starship = {
    enable = true;
    # custom settings
    settings = {
      add_newline = true;
      aws.disabled = false;
      gcloud.disabled = true;
      line_break.disabled = true;

    };
  };

  programs.direnv.enable = true;

  # # alacritty - a cross-platform, GPU-accelerated terminal emulator
  # programs.alacritty = {
  #   enable = true;
  #   # custom settings
  #   settings = {
  #     env.TERM = "xterm-256color";
  #     font = {
  #       size = 12;
  #       draw_bold_text_with_bright_colors = true;
  #     };
  #     scrolling.multiplier = 5;
  #     selection.save_to_clipboard = true;
  #   };
  # };

  # Helix - A post-modern text editor
  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = {
      theme = "tokyonight_storm";
      editor = {
        mouse = false;
        line-number = "relative";
        cursor-shape.insert = "bar";
        lsp.display-messages = true;
      };
      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
        esc = [ "collapse_selection" "keep_primary_selection" ];
      };
    };
    extraPackages = [
      pkgs.python312Packages.python-lsp-server
      pkgs.nil
      pkgs.yaml-language-server
      pkgs.marksman
      pkgs.bash-language-server
      # pkgs.
    ];
  };


  # Bash shell with starship prompt
  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      l = "ls";
      ll = "ls -la";
      la = "ls -a";
      gs = "git status";
      gl = "git log";
      g = "git";
      k = "kubectl";
    };
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin"
    '';
  };

  # Carapace - multi-shell completion engine
  programs.carapace = {
    enable = true;
    enableBashIntegration = true;
  };

  # SSH agent for key management (needed by Abacus, VS Code, etc.)
  services.ssh-agent = {
    enable = true;
    enableBashIntegration = true;
  };

  # Home-manager's zed produces read only `settings.json`, which limits features as changing models or settings at runtime.
  programs.zed-editor = {
  #   enable = true;
    extraPackages = [ pkgs.ansible-lint ];
  #   extensions = [
  #     "tokyo-night" # Theme
  #     "nix" #
  #     "dockerfile"
  #   ];

  #   userSettings = {
  #     terminal.env = {
  #       ZED = "1";
  #       TERM = "xterm-256color";
  #     };
  #      theme = {
  #      mode = "dark"; # = "system" for auto
  #      light = "Tokyo Night Light";
  #      dark = "Tokyo Night Storm";
  #      };
  #   };
  };

  # programs.bash = {
  #   enable = true;
  #   enableCompletion = true;
  #   # TODO add your custom bashrc here
  #   bashrcExtra = ''
  #     export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
  #   '';

  #   # set some aliases, feel free to add more or remove some
  #   shellAliases = {
  #     k = "kubectl";
  #     urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
  #     urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
  #   };
  # };

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.05";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
