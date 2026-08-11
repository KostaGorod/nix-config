# Memvid Repository Index

Memvid is available as a disabled workstation option:

```nix
programs.memvid.enable = true;
```

Enabling it installs `memvid` and `repo-mem`. The flake also exposes `memvid` as a package output.

`repo-mem` operates on the Git repository containing the current directory and stores all generated data in `.memvid/`. The directory is ignored by this repository and should be ignored in any repository where the tool is used.

```sh
repo-mem init
repo-mem index
repo-mem search "query"
repo-mem ask "question"
repo-mem status
repo-mem visualize
repo-mem clean
```

Indexes default to lexical search and `ask` defaults to a local Ollama model. `index`, `ensure`, and `visualize` write the shared index; use only one of them at a time. `search`, `ask`, `status`, and `show` are read-only.
