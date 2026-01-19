{
  lib,
  python3,
  gobject-introspection,
  wrapGAppsHook3,
  tlp,
}:

python3.pkgs.buildPythonApplication {
  pname = "tlp-power-profiles-bridge";
  version = "0.1.0";

  src = ./.;
  format = "other";

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook3
  ];

  propagatedBuildInputs = [
    python3.pkgs.pygobject3
  ];

  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/bin $out/share/dbus-1/system.d $out/lib/systemd/system
    
    cp tlp-power-profiles-bridge.py $out/bin/tlp-power-profiles-bridge
    chmod +x $out/bin/tlp-power-profiles-bridge
    
    # D-Bus system policy - restrict to root only
    cat > $out/share/dbus-1/system.d/net.hadess.PowerProfiles.conf << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- Only root can own the service -->
  <policy user="root">
    <allow own="net.hadess.PowerProfiles"/>
    <allow send_destination="net.hadess.PowerProfiles"/>
  </policy>

  <!-- All users can read properties and set profile -->
  <policy context="default">
    <allow send_destination="net.hadess.PowerProfiles"
           send_interface="org.freedesktop.DBus.Properties"
           send_member="Get"/>
    <allow send_destination="net.hadess.PowerProfiles"
           send_interface="org.freedesktop.DBus.Properties"
           send_member="GetAll"/>
    <allow send_destination="net.hadess.PowerProfiles"
           send_interface="org.freedesktop.DBus.Properties"
           send_member="Set"/>
    <allow send_destination="net.hadess.PowerProfiles"
           send_interface="org.freedesktop.DBus.Introspectable"/>
  </policy>
</busconfig>
EOF
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Bridge between TLP and power-profiles-daemon D-Bus API for COSMIC";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
