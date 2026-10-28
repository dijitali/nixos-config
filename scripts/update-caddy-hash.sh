#!/usr/bin/env bash
# Refresh the `hash` of a `caddy.withPlugins` package after its inputs moved.
#
# withPlugins vendors Caddy plus its plugins in a fixed-output derivation, so
# any change to Caddy's version (a nixpkgs bump) or to a plugin version changes
# that hash, and the build stops with "hash mismatch ... specified: X got: Y".
# This builds only that derivation (the package's `src`), and on a mismatch
# swaps X for Y in FILE. Renovate runs it as a post-upgrade task on the PRs
# that can cause one (renovate.json); run it by hand the same way.
#
#   scripts/update-caddy-hash.sh INSTALLABLE FILE [nix build args...]
#
# Evaluating the package never fetches the private site inputs (flake inputs
# are fetched on first use), so this works without their deploy keys.
set -euo pipefail

installable=${1:?usage: $0 INSTALLABLE FILE [nix build args...]}
file=${2:?usage: $0 INSTALLABLE FILE [nix build args...]}
shift 2

nix_build() {
  nix --extra-experimental-features 'nix-command flakes' build --no-link "$installable.src" "$@"
}

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if nix_build "$@" 2>"$log"; then
  echo "update-caddy-hash: $file is up to date"
  exit 0
fi

specified=$(sed -nE 's/^ *specified: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' "$log" | head -n1)
got=$(sed -nE 's/^ *got: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' "$log" | head -n1)
if [[ -z $specified || -z $got ]]; then
  echo "update-caddy-hash: build failed for a reason other than the hash:" >&2
  cat "$log" >&2
  exit 1
fi
if ! grep -qF "$specified" "$file"; then
  echo "update-caddy-hash: $specified (from the error) is not in $file" >&2
  exit 1
fi

# Base64 hashes contain / and +, never |.
sed -i "s|$specified|$got|" "$file"
echo "update-caddy-hash: $file: $specified -> $got"

# Confirm the new hash builds, so a PR never carries a guessed one.
nix_build "$@"
