#!/bin/bash
set -euo pipefail

VERSION="${1:-latest}"
REPO="stelaino/vision-ocr-mcp"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="vision-ocr-mcp"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || error "This tool requires macOS."

ARCH=$(uname -m)
case "$ARCH" in
  arm64)  ARCH_SUFFIX="macos-arm64" ;;
  x86_64) ARCH_SUFFIX="macos-amd64" ;;
  *)      error "Unsupported architecture: $ARCH" ;;
esac

if [ "$VERSION" = "latest" ]; then
  info "Fetching latest release..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  [ -n "$VERSION" ] || error "Failed to determine latest version"
fi

VERSION_NUM="${VERSION#v}"
TARBALL="${BINARY_NAME}-${VERSION_NUM}-${ARCH_SUFFIX}.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"

info "Downloading $BINARY_NAME $VERSION ($ARCH)..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "$TMPDIR/$TARBALL" || error "Download failed. Check version: $URL"
tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

if [ -w "$INSTALL_DIR" ]; then
  cp "$TMPDIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
else
  info "Installing to $INSTALL_DIR (requires sudo)..."
  sudo cp "$TMPDIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
fi
chmod +x "$INSTALL_DIR/$BINARY_NAME"

success "Installed $BINARY_NAME $VERSION to $INSTALL_DIR"
echo ""
echo "Quick start:"
echo "  # Start MCP server (stdio for Claude Desktop/Cursor)"
echo "  $BINARY_NAME serve"
echo ""
echo "  # Start HTTP server with Web UI"
echo "  $BINARY_NAME serve --transport http --port 8765 --ui"
echo ""
echo "  # Install as background service (auto-start at login)"
echo "  $BINARY_NAME service install --port 8765 --ui"
echo ""
echo "  # CLI OCR"
echo "  $BINARY_NAME ocr ~/Desktop/screenshot.png"
