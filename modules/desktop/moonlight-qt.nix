_: {
  nixos.modules.workstation = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      moonlight-qt
    ];
  };
}
