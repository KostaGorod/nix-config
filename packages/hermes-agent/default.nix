{
  lib,
  writeShellApplication,
  uv,
}:

let
  repository = "https://github.com/KostaGorod/hermes-agent.git";
  revision = "2e24e06e5513fa425ccf935d2e41991cb11ff383";
in
writeShellApplication {
  name = "hermes";
  runtimeInputs = [ uv ];
  text = ''
    export HERMES_NIX_BUILD=1
    exec uv tool run \
      --from "git+${repository}@${revision}" \
      hermes "$@"
  '';

  meta = {
    description = "Hermes agent from KostaGorod's pinned fork";
    homepage = "https://github.com/KostaGorod/hermes-agent";
    license = lib.licenses.mit;
    mainProgram = "hermes";
    platforms = lib.platforms.linux;
  };
}
