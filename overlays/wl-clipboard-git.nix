# wl-clipboard from git master with sensitive clipboard support
# The released 2.2.1 version doesn't have CLIPBOARD_STATE=sensitive support
# This is needed for password managers (Bitwarden, KeePassXC) to work with cliphist
_final: prev: {
  wl-clipboard-sensitive = prev.wl-clipboard.overrideAttrs (old: {
    version = "2.2.1-unstable-2025-11-24";

    src = prev.fetchFromGitHub {
      owner = "bugaevc";
      repo = "wl-clipboard";
      rev = "e8082035dafe0241739d7f7d16f7ecfd2ce06172"; # Latest commit with sensitive support
      hash = "sha256-sR/P+urw3LwAxwjckJP3tFeUfg5Axni+Z+F3mcEqznw=";
    };

    # Additional protocol dependency for ext-data-control-v1
    buildInputs = old.buildInputs ++ [ prev.wayland-protocols ];
  });
}
