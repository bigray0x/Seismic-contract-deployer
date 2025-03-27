#!/bin/bash

set -euo pipefail

# Detect OS
OS=$(uname -s)
echo "✅ Detected OS: $OS"

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' BOLD='' RESET=''
fi

error() { echo -e "${RED}❌ Error:${RESET} $*" >&2; exit 1; }
info() { echo -e "${GREEN}🔍${RESET} $*"; }
success() { echo -e "${GREEN}✅${RESET} $*"; }

# Install a package if missing
install_if_missing() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        info "Installing $cmd..."
        case "$OS" in
            Linux) sudo apt-get update && sudo apt-get install -y "$pkg" || error "Failed to install $pkg" ;;
            Darwin) brew install "$pkg" || error "Failed to install $pkg (ensure Homebrew is installed)" ;;
            *) error "Unsupported OS: $OS" ;;
        esac
        success "$cmd installed."
    else
        success "$cmd is already installed."
    fi
}

# Install Rust
if ! command -v rustc &>/dev/null; then
    info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || error "Failed to install Rust"
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    success "Rust installed."
else
    success "Rust is already installed."
fi

# Install jq
info "Installing required dependencies..."
install_if_missing "jq" "jq"

# Install Seismic Foundry tools
info "Installing Seismic Foundry tools..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash

# Avoid sourcing .bashrc to prevent "PS1: unbound variable" error
export PATH="$HOME/.seismic/bin:$PATH"

# Run sfoundryup
sfoundryup || error "Failed to install Seismic Foundry tools"

# Clone the Seismic Devnet repository
if [ ! -d "try-devnet" ]; then
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git || error "Failed to clone repository"
fi
cd try-devnet/packages/contract/

# Deploy contract
info "Deploying contract..."
bash script/deploy.sh

success "Contract deployed successfully!"
