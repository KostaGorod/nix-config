# nix-ld configuration for running dynamically linked binaries
# This enables tools like uv, poetry, and other Python package managers
# to work with precompiled binaries in virtual environments.
{ config, lib, pkgs, ... }:

{
  # Enable nix-ld to provide a dynamic linker for non-NixOS binaries
  programs.nix-ld = {
    enable = true;

    # Common libraries needed by Python packages and other dynamic binaries
    libraries = with pkgs; [
      # Core C/C++ runtime
      stdenv.cc.cc.lib  # libstdc++.so
      zlib              # Required by many Python packages
      glib              # GLib library

      # SSL/Crypto
      openssl           # SSL/TLS support

      # Compression
      bzip2
      xz
      zstd

      # Database bindings
      sqlite

      # Image processing (common in ML/data science)
      libpng
      libjpeg

      # XML processing
      libxml2
      expat

      # FFI
      libffi

      # Readline (for interactive shells)
      readline
      ncurses

      # Additional commonly needed libraries
      curl
      icu
    ];
  };
}
