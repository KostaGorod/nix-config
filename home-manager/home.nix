{ config, pkgs, lib, specialArgs, ... }:
let

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

    fastfetch
    nnn # terminal file manager
    
    # archives
    zip
    xz
    unzip
    p7zip

    # utils
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder
    tldr # Community man pages
    # git
    git-credential-oauth

    # knowledge base tools
    obsidian
    todoist-electron   
    # networking tools
    # mtr # A network diagnostic tool
    # iperf3
    dnsutils  # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    # aria2 # A lightweight multi-protocol & multi-source command-line download utility
    # socat # replacement of openbsd-netcat
    # nmap # A utility for network discovery and security auditing

    # misc #
    # cowsay
    file
    which
    tree
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

    btop  # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb

    # k8s and stuff
    kubectl
    k9s
    lens # GUI for k8s


    ##
    discord
    slack
  ];

  programs.vscode = {
    package = pkgs.vscode; #pkgs.vscodium
    enable = true;
    userSettings = {
      "window.titleBarStyle" = "custom"; # Use Vscode's TitleBarStyle instead of ugly wayland's
      "workbench.colorTheme" = "Tokyo Night Storm"; #apply theme
      ##
    };
    extensions = with pkgs; [
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

  # Git with oauth , using kwalletmanager to store the oauth token 
  programs.git = {
    package = pkgs.gitFull;
    enable = true;
    userName = "Kosta Gorod";
    userEmail = "korolx147@gmail.com";
    extraConfig = {
      credential.helper = lib.mkBefore [ "${pkgs.gitFull.override { withLibsecret = true; }}/bin/git-credential-libsecret" ];
    };
  };
  programs.git-credential-oauth.enable = true;

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

# Wezterm - terminal emulator
  programs.wezterm = {
    enable = true;
    # extraConfig = builtins.readFile ./wezterm.lua;
    extraConfig = ''
      return { 
        enable_scroll_var = true
      };
    #   color_scheme = "Catppuccin Frappe";
    #   font = wezterm.font("JetBrains Mono");
    '';
  };

# NuShell - Shell
  programs.nushell = {
    enable = true;
    shellAliases = {
      l = "ls";
      ll = "ls -la";
      la = "ls -a";
      gs = "git status";
      gl = "git log";
      g = "git";
      k = "kubectl";
    
    # rebuild  = "nixos-rebuild switch";
    };
    extraConfig = ''
      ####
     # let carapace_completer = {|spans|
     # carapace $spans.0 nushell $spans | from json
     # }
     $env.config = {
      show_banner: false,
      completions: {
      case_sensitive: false # case-sensitive completions
      quick: true    # set to false to prevent auto-selecting completions
      partial: true    # set to false to prevent partial filling of the prompt
      algorithm: "fuzzy"    # prefix or fuzzy
      # external: {
    #   # set to false to prevent nushell looking into $env.PATH to find more suggestions
          # enable: true 
    #   # set to lower can improve completion performance at the cost of omitting some options
          # max_results: 100 
          # completer: $carapace_completer # check 'carapace_completer' 
        # }
      }
     } 
     $env.PATH = ($env.PATH | 
     split row (char esep) |
     prepend /home/myuser/.apps |
     append /usr/bin/env
     )


    ########
    '';


    
  };
  programs.carapace= {
    enable = true;
    enableNushellIntegration = true;
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
