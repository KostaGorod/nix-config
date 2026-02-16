{ pkgs, ... }:

{
  programs.onlyoffice.enable = true;

  # OnlyOffice Spreadsheet can be strict about the requested font inside the grid.
  # If the sheet asks for Arial, the MS corefonts Arial on Linux often lacks Hebrew
  # glyphs, and OnlyOffice doesn't always fall back. Force a sensible substitute.
  fonts.fontconfig.localConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <match target="pattern">
        <test name="family" qual="any">
          <string>Arial</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
          <string>DejaVu Sans</string>
        </edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any">
          <string>ArialMT</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
          <string>DejaVu Sans</string>
        </edit>
      </match>
    </fontconfig>
  '';

  # onlyoffice has trouble with symlinks: https://github.com/ONLYOFFICE/DocumentServer/issues/1859
  # Do the copy at system activation time, targeted at the primary user.
  # This avoids relying on user activation hooks (which may run with HOME=/root).
  system.activationScripts.onlyofficeFonts = {
    text = ''
      user=kosta
      home=/home/$user
      if [ -d "$home" ]; then
        fontsDir="$home/.local/share/fonts"
        rm -rf "$fontsDir"
        install -d -m 755 -o "$user" -g users "$fontsDir" 2>/dev/null || install -d -m 755 -o "$user" "$fontsDir"

        # OnlyOffice can get "stuck" on the exact requested font (e.g. Arial) and
        # fail to fall back inside the spreadsheet grid. The Arial provided by
        # msttcorefonts often lacks Hebrew glyphs, so avoid installing it into the
        # per-user font dir that OnlyOffice prefers.
        for f in ${pkgs.corefonts}/share/fonts/truetype/*; do
          b="$(basename "$f")"
          case "$b" in
            Arial*.ttf|arial*.ttf) continue ;;
          esac
          cp -f "$f" "$fontsDir"/
        done

        # Provide Hebrew-capable fonts (otherwise you'll see missing-glyph boxes).
        cp -f ${pkgs.noto-fonts}/share/fonts/truetype/noto/*Hebrew* "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.dejavu_fonts}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.liberation_ttf}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true
        cp -f ${pkgs.culmus}/share/fonts/truetype/*.ttf "$fontsDir"/ 2>/dev/null || true

        chown -R "$user":users "$fontsDir" 2>/dev/null || chown -R "$user" "$fontsDir"
        chmod 444 "$fontsDir"/* 2>/dev/null || true
        su - "$user" -c '${pkgs.fontconfig}/bin/fc-cache -f >/dev/null 2>&1 || true' || true

        # Some OnlyOffice builds also scan an app-specific fonts directory.
        for d in \
          "$home/.local/share/onlyoffice/fonts" \
          "$home/.local/share/onlyoffice-desktopeditors/fonts" \
          "$home/.local/share/ONLYOFFICE/desktopeditors/fonts" \
          "$home/.local/share/OnlyOffice/desktopeditors/fonts" \
        ; do
          rm -rf "$d"
          install -d -m 755 -o "$user" -g users "$d" 2>/dev/null || install -d -m 755 -o "$user" "$d"
          cp -f "$fontsDir"/* "$d"/ 2>/dev/null || true
          chown -R "$user":users "$d" 2>/dev/null || chown -R "$user" "$d"
          chmod 444 "$d"/* 2>/dev/null || true
        done
      fi
    '';
  };
}
