# Adding Configuration

The repository uses the dendritic pattern. `flake.nix` recursively imports
every non-underscore Nix file below `modules/` as a flake-parts top-level
module. Do not add feature imports to `flake.nix` or create an aggregator list.

## Add A Workstation Feature

Create a file under the appropriate concern directory:

```nix
# modules/programs/example.nix
_: {
  nixos.modules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.example ];
    };
}
```

`import-tree` discovers the file, and every host importing
`config.nixos.modules.workstation` receives the contribution.

## Add A Kosta Package

Add it to `modules/users/kosta/packages.nix`, or create another user feature:

```nix
_: {
  nixos.modules.kosta =
    { pkgs, ... }:
    {
      users.users.kosta.packages = [ pkgs.example ];
    };
}
```

Use `users.users.kosta.packages` for user-only applications and
`environment.systemPackages` for host administration or shared programs.

## Add Host Policy

Host-specific settings merge directly into the host's deferred module:

```nix
# modules/hosts/rocinante/example.nix
_: {
  nixos.configurations.rocinante.module = {
    services.example.enable = true;
  };
}
```

Reusable option declarations should normally live in a feature contribution;
the host file should select policy by setting those options.

## Add A Host

Create a host composition that declares its architecture and broad modules:

```nix
{
  config,
  inputs,
  ...
}:
{
  nixos.configurations.new-host = {
    system = "x86_64-linux";
    module.imports = [
      inputs.disko.nixosModules.disko
      config.nixos.modules.workstation
    ];
  };
}
```

Additional files may merge into `nixos.configurations.new-host.module` without
editing the composition file.

## Excluded Files

`import-tree` ignores underscore-prefixed paths. Use them only for expressions
that must remain lower-level values, such as generated hardware configuration
or disko data imported by a host module. Package functions belong under
`packages/`, outside the auto-import tree.

## Verification

```sh
nix fmt
nix flake check --no-build
nix build .#checks.x86_64-linux.rocinante-toplevel
```
