#!/usr/bin/env bash
set -euo pipefail

usage="usage: package-smoke.sh PACKAGE_PATH EXPECTED_VERSION"
package=${1:?"$usage"}
expected_version=${2:?"$usage"}
app="$package/lib/claude-desktop/claude-desktop"
app_asar="$package/lib/claude-desktop/resources/app.asar"
desktop="$package/share/applications/com.anthropic.Claude.desktop"
virtiofsd="$package/lib/claude-desktop/resources/virtiofsd"
chrome_native_host="$package/lib/claude-desktop/resources/chrome-native-host"
github_mcp="$package/lib/claude-desktop/resources/app.asar.unpacked/resources/github-mcp/github-mcp-server"
search_provider="$package/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service"

test -x "$package/bin/claude-desktop"
test -x "$app"
test -x "$virtiofsd"
test -x "$chrome_native_host"
test -x "$github_mcp"
test ! -e "$package/lib/claude-desktop/chrome-sandbox"
test -f "$app_asar"
test -f "$desktop"
test -f "$search_provider"
find "$package/share/icons" -type f -iname '*claude*' -print -quit | grep -q .

grep -Fq "Exec=$package/bin/claude-desktop" "$desktop"
if grep -q '^Exec=claude-desktop' "$desktop"; then
  exit 1
fi
desktop-file-validate "$desktop"
grep -aFq 'process.env.CLAUDE_NIX_FIRMWARE' "$app_asar"
grep -aFq 'process.env.CLAUDE_NIX_VIRTIOFSD' "$app_asar"
grep -Fq "Exec=/nix/store/" "$search_provider"
grep -Fq "$package/lib/claude-desktop/resources/gnome-search-provider/searchProvider.js" "$search_provider"
grep -Fq "const EXECUTABLE = \"$package/bin/claude-desktop\";" \
  "$package/lib/claude-desktop/resources/gnome-search-provider/searchProvider.js"

for binary in "$app" "$virtiofsd" "$chrome_native_host"; do
  interpreter=$(patchelf --print-interpreter "$binary")
  [[ $interpreter == /nix/store/*/lib/ld-linux-x86-64.so.2 ]]
  patchelf --print-rpath "$binary" | grep -q /nix/store/
done

"$package/bin/claude-desktop" --version | grep -Fq "$expected_version"
