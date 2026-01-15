{
  lib,
  stdenv,
  autoPatchelfHook,
  makeWrapper,
  mono,
  steamworks-sdk-redist,
  zlib,
  icu,
  libdecor,
  waylandpp,
  cairo,
  pango,
  glib,
  dbus,
  yq-go,
  fetchSteam,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "scpsl-server";
  version = "8444671425106151572";
  src = fetchSteam {
    name = finalAttrs.pname;
    appId = "996560";
    depotId = "996562";
    manifestId = "8444671425106151572";
    hash = "sha256-9kPoFTJDcBgvUirv66W/aw8BcSFsvIgSJgVKzvWo2zo=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    yq-go
  ];

  buildInputs = [
    mono
    steamworks-sdk-redist
    zlib
    libdecor
    waylandpp
    cairo
    pango
    glib
    dbus
  ];

  runtimeDependencies = [
    icu
  ];

  dontBuild = true;
  dontConfigure = true;

  # Fix yaml errors
  postPatch = ''
    sed -Ei 's/\r//' \
      ConfigTemplates/*.template.txt

    sed -Ei 's/^([^:#]+:[[:space:]])(.*%.*)$/\1"\2"/' \
      ConfigTemplates/config_gameplay.template.txt

    substituteInPlace ConfigTemplates/config_gameplay.template.txt \
      --replace-fail '::' '"::"' \
      --replace-fail '0.0.0.0' '"0.0.0.0"' \
      --replace-fail 'the player stops' '# the player stops' \
      --replace-fail ' # Default is 10.' ""

    sed -Ei '/^#/d' \
      ConfigTemplates/*.template.txt

    yq -ri -I1 '.' ConfigTemplates/*.template.txt
    yq -ri -I1 '(.[][][] | select(kind == "seq")) style="flow"' \
      ConfigTemplates/config_remoteadmin.template.txt
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/scpsl-server
    cp -r \
      SCPSL_Data \
      ConfigTemplates \
      Translations \
      CreditsCache.json \
      SCPSL.x86_64 \
      *.so \
      LocalAdmin \
      $out/share/scpsl-server

    chmod +x $out/share/scpsl-server/{LocalAdmin,SCPSL.x86_64}

    runHook postInstall
  '';

  passthru.updateScript = [
    ./steam-update.sh
    finalAttrs.src.appId
    finalAttrs.src.depotId
    finalAttrs.pname
    "pkgs/scpsl-server/package.nix"
  ];

  meta = with lib; {
    description = "Some dedicated server";
    homepage = "https://steamdb.info/app/996560/";
    changelog = "https://store.steampowered.com/news/app/700330";
    sourceProvenance = with sourceTypes; [
      binaryNativeCode
      binaryBytecode
    ];
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
})
