{
  lib,
  stdenv,
  addDriverRunpath,
  alsa-lib,
  asar,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  coreutils,
  cups,
  dbus,
  desktop-file-utils,
  dpkg,
  expat,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  gjs,
  glib,
  gtk3,
  libayatana-appindicator,
  libcap_ng,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libseccomp,
  libuuid,
  libva,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
  makeWrapper,
  mesa,
  nspr,
  nss,
  OVMF,
  pango,
  perl,
  qemu_kvm,
  systemd,
  trash-cli,
  vulkan-loader,
  wayland,
  wrapGAppsHook3,
  writeShellScriptBin,
  xdg-utils,
}:

let
  source = import ./sources.nix;

  cleanXdgOpen = writeShellScriptBin "xdg-open" ''
    unset LD_LIBRARY_PATH GIO_EXTRA_MODULES GDK_PIXBUF_MODULE_FILE
    exec ${xdg-utils}/bin/xdg-open "$@"
  '';

  runtimeLibraries = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libayatana-appindicator
    libcap_ng
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    libseccomp
    libuuid
    libva
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    vulkan-loader
    wayland
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  inherit (source) version;

  src = fetchurl {
    name = "claude-desktop_${finalAttrs.version}_amd64.deb";
    inherit (source) url hash;
  };

  strictDeps = true;

  nativeBuildInputs = [
    asar
    autoPatchelfHook
    dpkg
    makeWrapper
    perl
    wrapGAppsHook3
  ];

  buildInputs = runtimeLibraries;

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar --extract --file - --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib" "$out/share"
    cp -a usr/lib/claude-desktop "$out/lib/"
    cp -a usr/share/applications usr/share/icons usr/share/doc "$out/share/"

    rm -f "$out/lib/claude-desktop/chrome-sandbox"

    substituteInPlace "$out/share/applications/com.anthropic.Claude.desktop" \
      --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop" \
      --replace-fail "Icon=claude-desktop" "Icon=$out/share/icons/hicolor/256x256/apps/claude-desktop.png"

    mkdir -p \
      "$out/share/dbus-1/services" \
      "$out/share/gnome-shell/search-providers"
    cp "$out/lib/claude-desktop/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service" \
      "$out/share/dbus-1/services/"
    cp "$out/lib/claude-desktop/resources/gnome-search-provider/com.anthropic.Claude.search-provider.ini" \
      "$out/share/gnome-shell/search-providers/"
    substituteInPlace "$out/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service" \
      --replace-fail \
        "Exec=/usr/bin/gjs -m /usr/lib/claude-desktop" \
        "Exec=${gjs}/bin/gjs -m $out/lib/claude-desktop"
    substituteInPlace "$out/lib/claude-desktop/resources/gnome-search-provider/searchProvider.js" \
      --replace-fail \
        'const EXECUTABLE = "claude-desktop";' \
        'const EXECUTABLE = "'$out'/bin/claude-desktop";' \
      --replace-fail \
        'const ICON_NAME = "claude-desktop";' \
        'const ICON_NAME = "'$out'/share/icons/hicolor/256x256/apps/claude-desktop.png";'

    appAsar="$out/lib/claude-desktop/resources/app.asar"
    asarRoot="$(mktemp -d)"
    asar extract "$appAsar" "$asarRoot"

    vmScript=$(grep -rlF '/usr/share/OVMF/OVMF_CODE_4M.fd' "$asarRoot/.vite/build")
    [[ $(printf '%s\n' "$vmScript" | grep -c .) == 1 ]] || {
      printf 'expected one Linux VM implementation, found: %s\n' "$vmScript" >&2
      exit 1
    }

    perl -0pi -e '
      s{process\.arch===([`\"])(arm64)\1\?\[\1/usr/share/AAVMF/AAVMF_CODE\.fd\1\]:\[\1/usr/share/OVMF/OVMF_CODE_4M\.fd\1,\1/usr/share/OVMF/OVMF_CODE\.fd\1\]}{process.env.CLAUDE_NIX_FIRMWARE?[process.env.CLAUDE_NIX_FIRMWARE]:process.arch===$1$2$1?[$1/usr/share/AAVMF/AAVMF_CODE.fd$1]:[$1/usr/share/OVMF/OVMF_CODE_4M.fd$1,$1/usr/share/OVMF/OVMF_CODE.fd$1]} or die "failed to add firmware override\n";
      s{\[([`\"])/usr/libexec/virtiofsd\1,\1/usr/bin/virtiofsd\1\]}{process.env.CLAUDE_NIX_VIRTIOFSD?[process.env.CLAUDE_NIX_VIRTIOFSD]:[$1/usr/libexec/virtiofsd$1,$1/usr/bin/virtiofsd$1]} or die "failed to add virtiofsd override\n";
    ' "$vmScript"

    rm -f "$asarRoot/compile-cache/$(basename "$vmScript").x64.jsc"
    asar list --is-pack "$appAsar" | sed -n 's/^unpack : //p' > "$asarRoot.original-unpacked"

    repackedAsar="$(mktemp -d)/app.asar"
    asar pack --unpack '{*.node,github-mcp-server}' "$asarRoot" "$repackedAsar"
    asar list --is-pack "$repackedAsar" | sed -n 's/^unpack : //p' > "$asarRoot.repacked-unpacked"
    cmp "$asarRoot.original-unpacked" "$asarRoot.repacked-unpacked"
    cp "$repackedAsar" "$appAsar"

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/lib/claude-desktop/.claude-desktop-wrapped" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${
        lib.makeBinPath [
          cleanXdgOpen
          glib
          qemu_kvm
          trash-cli
          xdg-utils
        ]
      }" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}:${addDriverRunpath.driverLink}/lib" \
      --prefix XDG_DATA_DIRS : "${addDriverRunpath.driverLink}/share" \
      --set CLAUDE_NIX_FIRMWARE "${OVMF.fd}/FV/OVMF_CODE.fd" \
      --set CLAUDE_NIX_VIRTIOFSD "$out/lib/claude-desktop/resources/virtiofsd" \
      --set-default ELECTRON_OZONE_PLATFORM_HINT auto

    cat > "$out/bin/claude-desktop" <<EOF
    #!${stdenv.shell}
    package_share="$out/share"
    desktop_source="$out/share/applications/com.anthropic.Claude.desktop"
    wrapped="$out/lib/claude-desktop/.claude-desktop-wrapped"
    mkdir_bin="${coreutils}/bin/mkdir"
    ln_bin="${coreutils}/bin/ln"
    readlink_bin="${coreutils}/bin/readlink"
    rm_bin="${coreutils}/bin/rm"
    update_desktop_database="${desktop-file-utils}/bin/update-desktop-database"
    xdg_mime="${xdg-utils}/bin/xdg-mime"
    EOF
    cat >> "$out/bin/claude-desktop" <<'EOF'
    data_home="''${XDG_DATA_HOME:-''${HOME:+$HOME/.local/share}}"
    if [ -n "$data_home" ]; then
      applications="$data_home/applications"
      desktop_target="$applications/com.anthropic.Claude.desktop"
      "$mkdir_bin" -p "$applications" 2>/dev/null
      if [ -e "$desktop_target" ] || [ -L "$desktop_target" ]; then
        desktop_current=$("$readlink_bin" -f -- "$desktop_target" 2>/dev/null || true)
        if [ "$desktop_current" != "$desktop_source" ]; then
          "$rm_bin" -f -- "$desktop_target"
        fi
      fi
      if [ ! -e "$desktop_target" ] && [ ! -L "$desktop_target" ]; then
        "$ln_bin" -s "$desktop_source" "$desktop_target"
      fi
      "$update_desktop_database" "$applications" >/dev/null 2>&1 || true
      XDG_DATA_DIRS="$package_share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}" \
        "$xdg_mime" default com.anthropic.Claude.desktop x-scheme-handler/claude \
        >/dev/null 2>&1 || true
    fi
    if [ -u /run/wrappers/bin/__chromium-suid-sandbox ]; then
      export CHROME_DEVEL_SANDBOX=/run/wrappers/bin/__chromium-suid-sandbox
    fi
    exec "$wrapped" "$@"
    EOF
    chmod +x "$out/bin/claude-desktop"
  '';

  passthru.updateScript = ./scripts/update.sh;

  meta = {
    description = "Official Claude Desktop application packaged for NixOS";
    homepage = "https://claude.ai/";
    downloadPage = "https://claude.ai/api/desktop/linux/x64/deb/latest/redirect";
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
