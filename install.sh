#!/bin/sh
# One-line installer for the mcptask runner (#11273).
#
#   curl -fsSL https://github.com/jchsoft/mcptask-releases/releases/latest/download/install.sh | sh
#
# That URL serves this script as published with the latest release, so it never
# drifts from the binaries it installs. The copy on the mirror's default branch
# is the same file, kept there for people who want to read it before running it.
#
# Downloads the release archive for this host, checks it against the published
# sha256, and puts `mcptask_runner` on PATH. Nothing else: it does not run
# `init`, and it does not install a scheduled job — those are decisions the
# operator makes afterwards, and an installer that made them from a pipe would
# be making them silently.
#
# Knobs, all optional:
#   MCPTASK_VERSION      tag to install, e.g. v0.1.0 (default: the latest release)
#   MCPTASK_INSTALL_DIR  where to put the binary (default: see below)
#   MCPTASK_RELEASE_REPO owner/name to download from (default: jchsoft/mcptask-releases)
#   GITHUB_TOKEN         only needed while the release repo is private
#
# POSIX sh on purpose: this runs on whatever /bin/sh a host happens to have,
# including dash and busybox, before the user has installed anything at all.
set -eu

REPO="${MCPTASK_RELEASE_REPO:-jchsoft/mcptask-releases}"
BINARY=mcptask_runner

info() { printf '%s\n' "$*"; }
# Failures go to stderr and exit non-zero, so `curl | sh` in a provisioning
# script stops rather than continuing without the binary it just "installed".
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" > /dev/null 2>&1 || die "$1 is required but not installed"; }

# curl or wget, whichever the host has - a minimal container often has only one.
#
# The token branches are spelled out rather than folded into a ${VAR:+...}
# expansion: the quotes inside such an expansion are literal, so the header
# would word-split into four arguments and the request would go out malformed.
download() { # download <url> <dest>
  if command -v curl > /dev/null 2>&1; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$2" "$1"
    else
      curl -fsSL -o "$2" "$1"
    fi
  else
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -qO "$2" --header="Authorization: Bearer $GITHUB_TOKEN" "$1"
    else
      wget -qO "$2" "$1"
    fi
  fi
}

command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1 ||
  die 'either curl or wget is required'
need tar
need uname

# --- what host is this -------------------------------------------------------

os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  darwin | linux) ;;
  mingw* | msys* | cygwin*)
    die 'on Windows install with scoop: scoop bucket add jchsoft https://github.com/jchsoft/scoop-bucket && scoop install mcptask_runner' ;;
  *) die "unsupported operating system: $os" ;;
esac

arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "unsupported architecture: $arch (the release builds amd64 and arm64)" ;;
esac

# --- which release -----------------------------------------------------------

tmp=$(mktemp -d)
# Runs on success and on failure alike, so a half-finished install leaves
# nothing behind in /tmp.
trap 'rm -rf "$tmp"' EXIT INT TERM

version="${MCPTASK_VERSION:-}"
if [ -z "$version" ]; then
  # /releases/latest redirects to the tag, and that redirect is not part of the
  # rate-limited API. This matters: api.github.com allows 60 unauthenticated
  # requests an hour *per IP*, so behind any shared address - an office NAT, a
  # CI runner, a VPN - the API answers 403 and the install fails for a reason
  # that has nothing to do with the host. GitHub's own macOS runners exhaust it
  # routinely, which is how this was found.
  if command -v curl > /dev/null 2>&1; then
    resolved=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
      "https://github.com/$REPO/releases/latest" 2> /dev/null || true)
    case "$resolved" in
      */releases/tag/*) version="${resolved##*/releases/tag/}" ;;
    esac
  fi

  # The API is the fallback: wget has no clean equivalent of the above, and a
  # repository with no published release gives a clearer answer here.
  if [ -z "$version" ]; then
    download "https://api.github.com/repos/$REPO/releases/latest" "$tmp/latest.json" ||
      die "cannot reach the release list for $REPO (rate-limited? private repo? set GITHUB_TOKEN)"
    # Read with sed rather than jq: a host that has not installed anything yet
    # very likely does not have jq either.
    version=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$tmp/latest.json" | head -n 1)
  fi

  [ -n "$version" ] || die "could not determine the latest release of $REPO"
fi

# Archive names carry the version without its leading v (goreleaser's .Version),
# while the tag keeps it. Both spellings are needed below, so derive rather than
# ask the caller to get it right.
bare_version="${version#v}"
archive="${BINARY}_${bare_version}_${os}_${arch}.tar.gz"
base="https://github.com/$REPO/releases/download/$version"

# --- download and verify -----------------------------------------------------

info "Downloading $archive ($version)"
download "$base/$archive" "$tmp/$archive" ||
  die "no such release asset: $archive - check that $version builds $os/$arch"
download "$base/checksums.txt" "$tmp/checksums.txt" ||
  die 'the release has no checksums.txt, refusing to install unverified'

# The checksum is the only thing standing between a compromised download and a
# binary that runs the operator's own Claude sessions, so a mismatch is fatal
# and never a warning.
#
# The entry has to be there before the check runs, because --ignore-missing (used
# below because only one of the six archives was downloaded) treats "this file is
# not in the list" as nothing to do rather than as a failure: GNU sha256sum exits
# 0 in that case. Without this line, a checksums.txt that simply omitted our
# archive would verify vacuously and install an unverified binary.
info 'Verifying checksum'
awk -v want="$archive" '{ sub(/^\*/, "", $2); if ($2 == want) found = 1 } END { exit !found }' \
  "$tmp/checksums.txt" || die "checksums.txt does not list $archive - refusing to install unverified"

(
  cd "$tmp"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum --ignore-missing --check checksums.txt > /dev/null
  elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 --ignore-missing --check checksums.txt > /dev/null
  else
    die 'neither sha256sum nor shasum is available to verify the download'
  fi
) || die "checksum mismatch for $archive - the download is not what the release published"

tar -xzf "$tmp/$archive" -C "$tmp"
[ -f "$tmp/$BINARY" ] || die "the archive did not contain $BINARY"

# --- install -----------------------------------------------------------------

# /usr/local/bin when it is already writable, ~/.local/bin otherwise. Deliberately
# no sudo: a script read off the internet through a pipe should not be the thing
# that asks for a root password. A host that wants it there can either pre-create
# the directory or re-run with MCPTASK_INSTALL_DIR set.
if [ -n "${MCPTASK_INSTALL_DIR:-}" ]; then
  dir="$MCPTASK_INSTALL_DIR"
elif [ -w /usr/local/bin ]; then
  dir=/usr/local/bin
else
  dir="$HOME/.local/bin"
fi

mkdir -p "$dir" || die "cannot create $dir"
# Install to a temporary name in the same directory and rename over the target:
# on Unix that swap is atomic, so upgrading never leaves a half-written binary,
# and a running process keeps the inode it started with.
cp "$tmp/$BINARY" "$dir/.$BINARY.new" || die "cannot write to $dir"
chmod 755 "$dir/.$BINARY.new"
mv -f "$dir/.$BINARY.new" "$dir/$BINARY" || die "cannot install into $dir"

info "Installed $BINARY $version to $dir"

case ":$PATH:" in
  *":$dir:"*) ;;
  *)
    info ''
    info "NOTE: $dir is not on your PATH. Add it:"
    info "  echo 'export PATH=\"$dir:\$PATH\"' >> ~/.profile"
    ;;
esac

info ''
info 'Next: run it in a project you want the runner to work on.'
info "  $BINARY init"
