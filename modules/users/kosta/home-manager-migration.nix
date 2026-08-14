_: {
  nixos.modules.kosta =
    { pkgs, ... }:
    let
      inherit (pkgs) coreutils;
      inherit (pkgs) findutils;
      home = "/home/kosta";
      marker = "/var/lib/nixos/home-manager-migration-v1";
    in
    {
      system.activationScripts.homeManagerMigration = {
        deps = [
          "users"
          "etc"
        ];
        text = ''
          marker=${marker}
          home=${home}

          if [ ! -e "$marker" ]; then
            migration_failed=0

            remove_legacy_link() {
              path="$1"
              relative="$2"

              if [ -L "$path" ]; then
                target="$(${coreutils}/bin/readlink "$path")"
                case "$target" in
                  /nix/store/*-home-manager-files/"$relative")
                    ${coreutils}/bin/rm -- "$path"
                    ;;
                  *)
                    echo "home-manager migration: refusing unexpected link $path -> $target" >&2
                    migration_failed=1
                    ;;
                esac
              elif [ -e "$path" ]; then
                echo "home-manager migration: refusing non-link path $path" >&2
                migration_failed=1
              fi
            }

            migrate_legacy_link() {
              path="$1"
              relative="$2"
              replacement="$3"

              if [ -L "$path" ]; then
                target="$(${coreutils}/bin/readlink "$path")"
                case "$target" in
                  /nix/store/*-home-manager-files/"$relative")
                    ${coreutils}/bin/rm -- "$path"
                    ${coreutils}/bin/ln -s "$replacement" "$path"
                    ;;
                  "$replacement")
                    ;;
                  *)
                    echo "home-manager migration: refusing unexpected link $path -> $target" >&2
                    migration_failed=1
                    ;;
                esac
              elif [ -e "$path" ]; then
                echo "home-manager migration: refusing non-link path $path" >&2
                migration_failed=1
              fi
            }

            remove_legacy_link "$home/.bash_profile" ".bash_profile"
            remove_legacy_link "$home/.bashrc" ".bashrc"
            remove_legacy_link "$home/.profile" ".profile"
            remove_legacy_link "$home/.cache/.keep" ".cache/.keep"
            remove_legacy_link "$home/.local/state/.keep" ".local/state/.keep"
            remove_legacy_link "$home/.config/environment.d/10-home-manager.conf" ".config/environment.d/10-home-manager.conf"
            remove_legacy_link "$home/.config/fontconfig/conf.d/10-hm-fonts.conf" ".config/fontconfig/conf.d/10-hm-fonts.conf"
            remove_legacy_link "$home/.config/fontconfig/conf.d/52-hm-default-fonts.conf" ".config/fontconfig/conf.d/52-hm-default-fonts.conf"
            remove_legacy_link "$home/.config/fuzzel/fuzzel.ini" ".config/fuzzel/fuzzel.ini"
            remove_legacy_link "$home/.config/git/config" ".config/git/config"
            remove_legacy_link "$home/.config/helix/config.toml" ".config/helix/config.toml"
            remove_legacy_link "$home/.config/starship.toml" ".config/starship.toml"
            remove_legacy_link "$home/.config/systemd/user/tray.target" ".config/systemd/user/tray.target"
            remove_legacy_link "$home/.zen/qodg0ptz.Default Profile/user.js" ".zen/qodg0ptz.Default Profile/user.js"

            migrate_legacy_link "$home/.config/Code/User/settings.json" ".config/Code/User/settings.json" "/etc/xdg/Code/User/settings.json"
            remove_legacy_link "$home/.config/gh/config.yml" ".config/gh/config.yml"

            remove_legacy_link "$home/.vscode/extensions/.extensions-immutable.json" ".vscode/extensions/.extensions-immutable.json"
            remove_legacy_link "$home/.vscode/extensions/MS-python.vscode-pylance" ".vscode/extensions/MS-python.vscode-pylance"
            remove_legacy_link "$home/.vscode/extensions/bbenoist.Nix" ".vscode/extensions/bbenoist.Nix"
            remove_legacy_link "$home/.vscode/extensions/enkia.tokyo-night" ".vscode/extensions/enkia.tokyo-night"
            remove_legacy_link "$home/.vscode/extensions/github.copilot" ".vscode/extensions/github.copilot"
            remove_legacy_link "$home/.vscode/extensions/github.copilot-chat" ".vscode/extensions/github.copilot-chat"
            remove_legacy_link "$home/.vscode/extensions/ms-pyright.pyright" ".vscode/extensions/ms-pyright.pyright"
            remove_legacy_link "$home/.vscode/extensions/ms-python.black-formatter" ".vscode/extensions/ms-python.black-formatter"
            remove_legacy_link "$home/.vscode/extensions/ms-python.debugpy" ".vscode/extensions/ms-python.debugpy"
            remove_legacy_link "$home/.vscode/extensions/ms-python.python" ".vscode/extensions/ms-python.python"
            remove_legacy_link "$home/.vscode/extensions/ms-vscode-remote.remote-ssh" ".vscode/extensions/ms-vscode-remote.remote-ssh"
            remove_legacy_link "$home/.vscode/extensions/ms-vscode-remote.remote-ssh-edit" ".vscode/extensions/ms-vscode-remote.remote-ssh-edit"

            remaining_legacy_links="$(${findutils}/bin/find "$home" -xdev -type l -print0 | while IFS= read -r -d "" path; do
              target="$(${coreutils}/bin/readlink "$path")"
              case "$target" in
                /nix/store/*-home-manager-files/*)
                  printf '%s\n' "$path"
                  ;;
              esac
            done)"

            if [ -n "$remaining_legacy_links" ]; then
              echo "home-manager migration: legacy links remain:" >&2
              printf '%s\n' "$remaining_legacy_links" >&2
              migration_failed=1
            fi

            if [ "$migration_failed" -eq 0 ]; then
              profile_dir="$home/.local/state/nix/profiles"
              profile="$profile_dir/home-manager"

              if [ -L "$profile" ]; then
                profile_target="$(${coreutils}/bin/readlink "$profile")"
                case "$profile_target" in
                  home-manager-[0-9]*-link)
                    generation_link="$profile_dir/$profile_target"
                    if [ -L "$generation_link" ]; then
                      generation_target="$(${coreutils}/bin/readlink "$generation_link")"
                      case "$generation_target" in
                        /nix/store/*-home-manager-generation)
                          ${coreutils}/bin/rm -- "$profile" "$generation_link"
                          ;;
                        *)
                          echo "home-manager migration: refusing unexpected generation $generation_link -> $generation_target" >&2
                          migration_failed=1
                          ;;
                      esac
                    else
                      echo "home-manager migration: missing generation link $generation_link" >&2
                      migration_failed=1
                    fi
                    ;;
                  *)
                    echo "home-manager migration: refusing unexpected profile $profile -> $profile_target" >&2
                    migration_failed=1
                    ;;
                esac
              elif [ -e "$profile" ]; then
                echo "home-manager migration: refusing non-link profile $profile" >&2
                migration_failed=1
              fi

              gcroot="$home/.local/state/home-manager/gcroots/current-home"
              if [ -L "$gcroot" ]; then
                gcroot_target="$(${coreutils}/bin/readlink "$gcroot")"
                case "$gcroot_target" in
                  /nix/store/*-home-manager-generation)
                    ${coreutils}/bin/rm -- "$gcroot"
                    ;;
                  *)
                    echo "home-manager migration: refusing unexpected gc root $gcroot -> $gcroot_target" >&2
                    migration_failed=1
                    ;;
                esac
              elif [ -e "$gcroot" ]; then
                echo "home-manager migration: refusing non-link gc root $gcroot" >&2
                migration_failed=1
              fi
            fi

            if [ "$migration_failed" -eq 0 ]; then
              ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$marker")"
              ${coreutils}/bin/touch "$marker"
            else
              echo "home-manager migration: incomplete; retrying on the next activation" >&2
            fi
          fi
        '';
      };
    };
}
