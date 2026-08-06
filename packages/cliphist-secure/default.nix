{
  bash,
  cliphist,
  coreutils,
  findutils,
  gocryptfs,
  gnugrep,
  lib,
  libsecret,
  openssl,
  shellcheck,
  stdenvNoCC,
  systemd,
  util-linux,
}:

stdenvNoCC.mkDerivation {
  pname = "cliphist-secure";
  version = "0.1.0";

  src = ./.;

  strictDeps = true;
  dontBuild = true;
  doCheck = true;

  nativeBuildInputs = [ shellcheck ];

  checkPhase = ''
    runHook preCheck

    shellcheck --shell bash --exclude=SC2239 cliphist cliphist-vault tests.sh
    ${bash}/bin/bash ./tests.sh

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 cliphist "$out/bin/cliphist"
    install -Dm755 cliphist-vault "$out/libexec/cliphist-vault"

    substituteInPlace "$out/bin/cliphist" \
      --replace-fail '@bash@' '${bash}/bin/bash' \
      --replace-fail '@cliphist@' '${cliphist}/bin/cliphist' \
      --replace-fail '@mountpoint@' '${util-linux}/bin/mountpoint' \
      --replace-fail '@systemctl@' '${systemd}/bin/systemctl' \
      --replace-fail '@install@' '${coreutils}/bin/install' \
      --replace-fail '@chmod@' '${coreutils}/bin/chmod' \
      --replace-fail '@rm@' '${coreutils}/bin/rm'

    substituteInPlace "$out/libexec/cliphist-vault" \
      --replace-fail '@bash@' '${bash}/bin/bash' \
      --replace-fail '@secret_tool@' '${libsecret}/bin/secret-tool' \
      --replace-fail '@openssl@' '${openssl}/bin/openssl' \
      --replace-fail '@gocryptfs@' '${gocryptfs}/bin/gocryptfs' \
      --replace-fail '@mountpoint@' '${util-linux}/bin/mountpoint' \
      --replace-fail '@fusermount@' '/run/wrappers/bin/fusermount' \
      --replace-fail '@install@' '${coreutils}/bin/install' \
      --replace-fail '@chmod@' '${coreutils}/bin/chmod' \
      --replace-fail '@stat@' '${coreutils}/bin/stat' \
      --replace-fail '@find@' '${findutils}/bin/find' \
      --replace-fail '@grep@' '${gnugrep}/bin/grep' \
      --replace-fail '@rm@' '${coreutils}/bin/rm' \
      --replace-fail '@rmdir@' '${coreutils}/bin/rmdir' \
      --replace-fail '@sleep@' '${coreutils}/bin/sleep'

    runHook postInstall
  '';

  meta = {
    description = "Encrypted cliphist storage backed by GNOME Keyring and gocryptfs";
    license = lib.licenses.mit;
    mainProgram = "cliphist";
    platforms = lib.platforms.linux;
  };
}
