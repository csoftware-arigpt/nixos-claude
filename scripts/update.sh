#!/usr/bin/env bash
set -euo pipefail

readonly repository="https://downloads.claude.ai/claude-desktop/apt/stable"
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly repository_root
temporary_directory=$(mktemp -d)
readonly temporary_directory
trap 'rm -rf "$temporary_directory"' EXIT

readonly packages="$temporary_directory/Packages"
curl --fail --location --retry 3 --silent --show-error \
  --output "$packages" \
  "$repository/dists/stable/main/binary-amd64/Packages"

latest=$(
  awk '
    BEGIN { RS=""; FS="\n" }
    {
      package = version = architecture = filename = sha256 = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Package: /) package = substr($i, 10)
        else if ($i ~ /^Version: /) version = substr($i, 10)
        else if ($i ~ /^Architecture: /) architecture = substr($i, 15)
        else if ($i ~ /^Filename: /) filename = substr($i, 11)
        else if ($i ~ /^SHA256: /) sha256 = substr($i, 9)
      }
      if (package == "claude-desktop")
        print version "\t" architecture "\t" filename "\t" sha256
    }
  ' "$packages" | sort -V -k1,1 | tail -n 1
)

IFS=$'\t' read -r version architecture filename sha256 <<<"$latest"
[[ $version =~ ^[0-9]+([.][0-9]+)+$ ]] || {
  printf 'unexpected Debian version: %s\n' "$version" >&2
  exit 1
}
[[ $architecture == amd64 ]] || {
  printf 'unexpected Debian architecture: %s\n' "$architecture" >&2
  exit 1
}
[[ $filename == "pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb" ]] || {
  printf 'unexpected Debian filename: %s\n' "$filename" >&2
  exit 1
}
[[ $sha256 =~ ^[0-9a-f]{64}$ ]] || {
  printf 'unexpected SHA-256: %s\n' "$sha256" >&2
  exit 1
}

url="$repository/$filename"
hash=$(nix hash convert --hash-algo sha256 --to sri "$sha256")
new_source="$temporary_directory/sources.nix"
new_readme="$temporary_directory/README.md"

cat >"$new_source" <<EOF
{
  version = "$version";
  url = "$url";
  hash = "$hash";
}
EOF

if cmp --silent "$new_source" "$repository_root/sources.nix"; then
  updated_at=$(sed -n "s/^Last package update: \`\\(.*\\)\`\\.\$/\\1/p" \
    "$repository_root/README.md")
  [[ -n $updated_at ]] || updated_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
else
  updated_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
fi

awk -v version="$version" -v updated_at="$updated_at" '
  /^Current packaged version:/ {
    print "Current packaged version: `" version "`."
    print "Last package update: `" updated_at "`."
    next
  }
  /^Last package update:/ { next }
  { print }
' "$repository_root/README.md" >"$new_readme"

if cmp --silent "$new_source" "$repository_root/sources.nix" \
  && cmp --silent "$new_readme" "$repository_root/README.md"; then
  printf 'Claude Desktop %s is already pinned.\n' "$version"
  exit 0
fi

mv "$new_source" "$repository_root/sources.nix"
mv "$new_readme" "$repository_root/README.md"
printf 'Pinned Claude Desktop %s (%s).\n' "$version" "$hash"
