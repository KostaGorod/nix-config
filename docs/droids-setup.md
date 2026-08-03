# FactoryAI Droids Setup

Droids is installed from the `llm-agents` input by the auto-imported feature
module at `modules/programs/droids.nix`.

The workstation contribution enables it in
`modules/programs/workstation.nix`:

```nix
programs.droids.enable = true;
```

After rebuilding, run it from a project directory:

```sh
droid
```

The module also installs `xdg-utils` and sets `FACTORY_CONFIG_HOME` to
`$HOME/.config/factory`. The standalone flake in `flakes/droids/` is not used
by the active NixOS configuration; it is retained for independent packaging
and testing.

To disable Droids for every workstation host, change the enable declaration in
`modules/programs/workstation.nix`. To choose a different package, override the
module option from a host contribution:

```nix
programs.droids.package = inputs.some-input.packages.${pkgs.system}.default;
```
