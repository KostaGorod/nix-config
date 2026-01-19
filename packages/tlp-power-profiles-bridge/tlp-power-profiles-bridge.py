#!/usr/bin/env python3
"""
TLP to power-profiles-daemon D-Bus Bridge

Provides the net.hadess.PowerProfiles D-Bus interface that COSMIC expects,
but translates requests to TLP commands.

Security considerations:
- Runs as root (required for TLP)
- Uses system D-Bus (polkit protected)
- Strict input validation (only known profile names)
- No shell execution (subprocess with list args)
- Rate limiting on profile changes

Profile mapping:
- power-saver   -> tlp bat
- balanced      -> tlp start (auto mode)
- performance   -> tlp ac
"""

import subprocess
import time
import os
import sys
from typing import Optional

# Use GLib/Gio for D-Bus (standard, secure)
import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib

# Constants
DBUS_NAME = "net.hadess.PowerProfiles"
DBUS_PATH = "/net/hadess/PowerProfiles"

# Valid profiles - strict whitelist
VALID_PROFILES = frozenset(["power-saver", "balanced", "performance"])

# TLP binary path - will be set by NixOS wrapper
TLP_PATH = os.environ.get("TLP_PATH", "/run/current-system/sw/bin/tlp")

# Rate limiting: minimum seconds between profile changes
RATE_LIMIT_SECONDS = 2
last_change_time = 0

# D-Bus interface XML
INTERFACE_XML = """
<node>
  <interface name="net.hadess.PowerProfiles">
    <property name="ActiveProfile" type="s" access="readwrite"/>
    <property name="PerformanceInhibited" type="s" access="read"/>
    <property name="Profiles" type="aa{sv}" access="read"/>
    <property name="Actions" type="as" access="read"/>
  </interface>
</node>
"""


def get_tlp_mode() -> str:
    """Get current TLP mode by checking tlp-stat."""
    try:
        result = subprocess.run(
            [TLP_PATH + "-stat", "-s"],
            capture_output=True,
            text=True,
            timeout=5
        )
        output = result.stdout.lower()
        
        if "mode = ac" in output:
            return "performance"
        elif "mode = battery" in output:
            return "power-saver"
        else:
            return "balanced"
    except Exception as e:
        print(f"Error getting TLP mode: {e}", file=sys.stderr)
        return "balanced"


def set_tlp_mode(profile: str) -> bool:
    """Set TLP mode. Returns True on success."""
    global last_change_time
    
    # Security: strict profile validation
    if profile not in VALID_PROFILES:
        print(f"Security: rejected invalid profile '{profile}'", file=sys.stderr)
        return False
    
    # Rate limiting
    now = time.time()
    if now - last_change_time < RATE_LIMIT_SECONDS:
        print(f"Rate limited: too fast", file=sys.stderr)
        return False
    
    # Map profile to TLP command
    if profile == "power-saver":
        cmd = [TLP_PATH, "bat"]
    elif profile == "performance":
        cmd = [TLP_PATH, "ac"]
    else:  # balanced
        cmd = [TLP_PATH, "start"]
    
    try:
        # Security: no shell=True, direct exec
        result = subprocess.run(
            cmd,
            capture_output=True,
            timeout=10
        )
        
        if result.returncode == 0:
            last_change_time = now
            print(f"Set profile to {profile}", file=sys.stderr)
            return True
        else:
            print(f"TLP error: {result.stderr.decode()}", file=sys.stderr)
            return False
            
    except Exception as e:
        print(f"Error setting TLP mode: {e}", file=sys.stderr)
        return False


def check_performance_inhibited() -> str:
    """Check if performance mode is inhibited (e.g., on battery)."""
    try:
        # Check if on battery
        with open("/sys/class/power_supply/AC/online", "r") as f:
            if f.read().strip() == "0":
                return "on-battery"
    except FileNotFoundError:
        pass
    
    # Check thermal throttling
    try:
        for i in range(10):
            path = f"/sys/class/thermal/thermal_zone{i}/temp"
            if os.path.exists(path):
                with open(path, "r") as f:
                    temp = int(f.read().strip()) / 1000
                    if temp > 85:  # 85°C threshold
                        return "high-operating-temperature"
    except Exception:
        pass
    
    return ""


class PowerProfilesService:
    """D-Bus service implementing net.hadess.PowerProfiles."""
    
    def __init__(self):
        self.current_profile = get_tlp_mode()
        self.connection = None
        self.registration_id = None
        
    def _get_profiles(self):
        """Return available profiles in D-Bus format."""
        return [
            {"Profile": GLib.Variant("s", "power-saver"), 
             "Driver": GLib.Variant("s", "tlp"),
             "CpuDriver": GLib.Variant("s", "tlp")},
            {"Profile": GLib.Variant("s", "balanced"),
             "Driver": GLib.Variant("s", "tlp"),
             "CpuDriver": GLib.Variant("s", "tlp")},
            {"Profile": GLib.Variant("s", "performance"),
             "Driver": GLib.Variant("s", "tlp"),
             "CpuDriver": GLib.Variant("s", "tlp")},
        ]
    
    def _handle_method_call(self, connection, sender, object_path, interface_name,
                            method_name, parameters, invocation):
        """Handle D-Bus method calls."""
        # net.hadess.PowerProfiles doesn't define methods, only properties
        invocation.return_error_literal(
            Gio.dbus_error_quark(),
            Gio.DBusError.UNKNOWN_METHOD,
            f"Unknown method: {method_name}"
        )
    
    def _handle_get_property(self, connection, sender, object_path,
                             interface_name, property_name):
        """Handle D-Bus property reads."""
        if property_name == "ActiveProfile":
            self.current_profile = get_tlp_mode()
            return GLib.Variant("s", self.current_profile)
        elif property_name == "PerformanceInhibited":
            return GLib.Variant("s", check_performance_inhibited())
        elif property_name == "Profiles":
            profiles = self._get_profiles()
            return GLib.Variant("aa{sv}", profiles)
        elif property_name == "Actions":
            return GLib.Variant("as", [])
        
        return None
    
    def _handle_set_property(self, connection, sender, object_path,
                             interface_name, property_name, value):
        """Handle D-Bus property writes."""
        if property_name == "ActiveProfile":
            new_profile = value.get_string()
            
            # Security: validate before processing
            if new_profile not in VALID_PROFILES:
                print(f"Security: rejected invalid profile from {sender}", file=sys.stderr)
                return False
            
            if set_tlp_mode(new_profile):
                self.current_profile = new_profile
                # Emit PropertiesChanged signal
                changed = {"ActiveProfile": GLib.Variant("s", new_profile)}
                self.connection.emit_signal(
                    None,
                    DBUS_PATH,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    GLib.Variant("(sa{sv}as)", (interface_name, changed, []))
                )
                return True
            
        return False
    
    def run(self):
        """Start the D-Bus service."""
        # Security: verify running as root (required for TLP)
        if os.geteuid() != 0:
            print("Error: must run as root for TLP access", file=sys.stderr)
            sys.exit(1)
        
        # Verify TLP exists
        if not os.path.exists(TLP_PATH):
            print(f"Error: TLP not found at {TLP_PATH}", file=sys.stderr)
            sys.exit(1)
        
        # Get system bus
        self.connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        
        # Request the bus name
        Gio.bus_own_name_on_connection(
            self.connection,
            DBUS_NAME,
            Gio.BusNameOwnerFlags.NONE,
            None,  # name_acquired_callback
            lambda conn, name: print(f"Lost bus name {name}", file=sys.stderr) or sys.exit(1)
        )
        
        # Parse interface XML
        node_info = Gio.DBusNodeInfo.new_for_xml(INTERFACE_XML)
        interface_info = node_info.lookup_interface(DBUS_NAME)
        
        # Register object
        self.registration_id = self.connection.register_object(
            DBUS_PATH,
            interface_info,
            self._handle_method_call,
            self._handle_get_property,
            self._handle_set_property
        )
        
        print(f"TLP power-profiles bridge started", file=sys.stderr)
        print(f"Current profile: {self.current_profile}", file=sys.stderr)
        
        # Run main loop
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            print("Shutting down...", file=sys.stderr)


if __name__ == "__main__":
    service = PowerProfilesService()
    service.run()
