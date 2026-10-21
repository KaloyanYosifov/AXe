#!/usr/bin/env bash
# Builds AXe from this checkout and installs it with Homebrew.
#
# The build skips Developer ID signing and notarization. The payload goes into a
# local tap formula with a file:// URL, so Homebrew owns the install and its
# post_install step ad-hoc signs the binaries.
#
# Usage: scripts/install-from-source.sh
#
# Environment:
#   AXE_TAP      Local tap for the formula (default: local/axe)
#   AXE_VERSION  Version for the formula and `axe --version`
#                (default: git describe --tags --always --dirty)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

AXE_TAP="${AXE_TAP:-local/axe}"
AXE_VERSION="${AXE_VERSION:-$(git describe --tags --always --dirty)}"
export AXE_VERSION

BUILD_OUTPUT_DIR="${REPO_ROOT}/build_products"
HOMEBREW_OUTPUT_DIR="${BUILD_OUTPUT_DIR}/homebrew"
STAGE_DIR="${HOMEBREW_OUTPUT_DIR}/stage"
ARCHIVE_PATH="${HOMEBREW_OUTPUT_DIR}/axe-${AXE_VERSION}.tar.gz"

for tool in brew git swift xcodebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: ${tool} is not installed." >&2
    exit 1
  fi
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen..."
  brew install xcodegen
fi

echo "==> Building AXe ${AXE_VERSION}..."
for step in setup clean frameworks install strip xcframeworks executable; do
  scripts/build.sh "$step"
done

echo "==> Creating the Homebrew archive..."
mkdir -p "$HOMEBREW_OUTPUT_DIR"
scripts/release-artifacts.sh stage-build-output --build-output-dir "$BUILD_OUTPUT_DIR" --stage-dir "$STAGE_DIR"
scripts/release-artifacts.sh create-homebrew-archive --stage-dir "$STAGE_DIR" --archive "$ARCHIVE_PATH"
ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"

echo "==> Writing the formula to the ${AXE_TAP} tap..."
if ! brew tap | grep -Fqx "$AXE_TAP"; then
  brew tap-new --no-git "$AXE_TAP"
fi
TAP_DIR="$(brew --repository "$AXE_TAP")"
mkdir -p "${TAP_DIR}/Formula"
scripts/generate-homebrew-formula.sh \
  --formula-class Axe \
  --homepage "https://github.com/KaloyanYosifov/AXe" \
  --version "$AXE_VERSION" \
  --url "file://${ARCHIVE_PATH}" \
  --sha256 "$ARCHIVE_SHA256" \
  > "${TAP_DIR}/Formula/axe.rb"

echo "==> Installing ${AXE_TAP}/axe..."
if brew list --formula "${AXE_TAP}/axe" >/dev/null 2>&1; then
  brew reinstall "${AXE_TAP}/axe"
else
  brew install "${AXE_TAP}/axe"
fi

axe --version
