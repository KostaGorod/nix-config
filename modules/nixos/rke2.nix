{
  lib,
  inputs,
  ...
}:

{
  imports = [
    inputs.rke2.nixosModules.default
  ];

  # Don't interfere with k8s networking
  networking.firewall.enable = lib.mkForce false;

  services.numtide-rke2 = {
    enable = true;
    role = "server";
    extraFlags = [
      "--disable"
      "rke2-ingress-nginx"
    ];
    settings.kube-apiserver-arg = [
      "anonymous-auth=false"
    ];
    settings.tls-san = [
      "<TODO>"
    ];
    settings.write-kubeconfig-mode = "0644";
  };
}
