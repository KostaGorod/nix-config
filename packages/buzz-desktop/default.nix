{
  appimageTools,
  fetchurl,
  gst_all_1,
  lib,
}:
let
  pname = "buzz-desktop";
  version = "0.5.23";
  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v${version}/Buzz_${version}_amd64.AppImage";
    hash = "sha256-9brR7eui1jQ+QQLpziuu1M2kpt/RarqjMIG/rbxfnU4=";
  };

  gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
  ];

  # The bundle ships WebKitGTK but no GStreamer core (upstream's
  # fix-appimage.sh removed it, expecting host GStreamer). Upstream's
  # usr/bin/buzz-desktop shim unsets any GST_PLUGIN_* var pointing into the
  # appdir so the system GStreamer default path takes over — which works on
  # FHS hosts but is empty inside the bwrap sandbox, leaving WebKit with
  # zero plugins and a blank window. Re-export the nix store plugin dirs
  # after the shim's unset loop, just before it execs the real binary.
  shimPatch = ''
    export BUZZ_RELAY_URL="''${BUZZ_RELAY_URL:-wss://dev-vm.myth-rudd.ts.net:3000}"
    export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
    export GST_PLUGIN_SYSTEM_PATH="${gstPluginPath}"
    export GST_PLUGIN_SCANNER="${gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner"
    export GST_PLUGIN_SCANNER_1_0="${gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner"
    # The host cache points at a librsvg loader built against a newer
    # gdk-pixbuf than the bundled one; unset it so the bundled pixbuf
    # resolves its own loaders via the default FHS path.
    unset GDK_PIXBUF_MODULE_FILE'';

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
    postExtract = ''
        substituteInPlace $out/usr/bin/buzz-desktop \
          --replace-fail 'exec -a "buzz-desktop"' '${"\n"}${shimPatch}
      exec -a "buzz-desktop"'
    '';
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # wrapType2's default runScript re-extracts the original AppImage via
  # appimage-exec, bypassing postExtract. Exec the patched extraction's
  # stock AppRun.wrapped directly instead — the shim inside it carries the
  # GST patch.
  runScript = "${appimageContents}/AppRun.wrapped";

  # webkitgtk_4_1's closure supplies the GStreamer core libs inside the
  # sandbox; the rest close the bundle's dlopen edges (libelf/libzstd via
  # libdw, libffi via gnutls, colord via the cups print backend).
  extraPkgs =
    pkgs: with pkgs; [
      glib
      gsettings-desktop-schemas
      webkitgtk_4_1
      elfutils
      zstd
      libffi
      colord
      zlib
    ];

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/Buzz.desktop $out/share/applications/${pname}.desktop
    cp -r ${appimageContents}/usr/share/icons $out/share/
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=buzz-desktop' "Exec=$out/bin/${pname}"
  '';

  meta = {
    description = "Buzz desktop app — a workspace where humans and agents build together";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
