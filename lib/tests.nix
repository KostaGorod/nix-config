{ pkgs, lib, ... }:

{
  # Abstract: Run a simple boolean check and return a success derivation if true
  # Use this for "close to source" logic validation without full evaluation
  runTest =
    name: condition:
    if condition then pkgs.runCommand "test-${name}" { } "touch $out" else throw "Test failed: ${name}";

  # Helper to aggregate checks from multiple test files
  mkChecks =
    args: testFiles:
    lib.foldl' (
      acc: path:
      let
        name = lib.removeSuffix ".test.nix" (builtins.baseNameOf path);
        testOutput = import path (args // { inherit name; });
      in
      acc // (lib.mapAttrs' (n: v: lib.nameValuePair "${name}-${n}" v) testOutput.checks)
    ) { } testFiles;
}
