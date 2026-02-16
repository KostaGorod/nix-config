# User services for kosta
{ pkgs, ... }:
{
  # Keep OnlyOffice Desktop Editors fed with real font files.
  # Some OnlyOffice builds don't fully rely on system fontconfig and instead
  # scan an app-local fonts directory for the font picker + spreadsheet grid.
  systemd.user.services.onlyoffice-fonts = {
    Unit = {
      Description = "Sync Hebrew-capable fonts for OnlyOffice";
      After = [ "graphical-session-pre.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "onlyoffice-fonts" ''
        set -euo pipefail

        fontsDir="$HOME/.local/share/onlyoffice/desktopeditors/fonts"
        mkdir -p "$fontsDir"
        rm -f "$fontsDir"/* || true

        # Hebrew-capable fonts
        cp -f ${pkgs.noto-fonts}/share/fonts/truetype/noto/*Hebrew* "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.dejavu_fonts}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.liberation_ttf}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.culmus}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true

        # Refresh user font cache (helps other apps too)
        ${pkgs.fontconfig}/bin/fc-cache -f >/dev/null 2>&1 || true
      '';
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
