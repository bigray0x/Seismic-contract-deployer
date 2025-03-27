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

# Function to install missing dependencies
install_if_missing() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        info "Installing $cmd..."
        case "$OS" in
            Linux) sudo apt update && sudo apt install -y "$pkg" || error "Failed to install $pkg" ;;
            Darwin) brew install "$pkg" || error "Failed to install $pkg (ensure Homebrew is installed)" ;;
            *) error "Unsupported OS: $OS" ;;
        esac
        success "$cmd installed."
    else
        success "$cmd is already installed."
    fi
}

# Step 1: Install Rust
info "Installing Rust..."
curl https://sh.rustup.rs -sSf | sh -s -- -y || error "Failed to install Rust"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
success "Rust installed."

# Step 2: Install jq
info "Installing jq..."
install_if_missing "jq" "jq"

# Step 3: Install sfoundryup
info "Installing Seismic Foundry tools..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash || error "Failed to install sfoundryup"

source "$HOME/.bashrc"
sfoundryup || error "sfoundryup installation failed."
success "Seismic Foundry tools installed."

# Step 4: Clone Seismic Devnet Repository
info "Cloning the Seismic Devnet repository..."
git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git || error "Failed to clone repository"
cd try-devnet/packages/contract/ || error "Failed to navigate to contract directory"
success "Repository cloned."

# Step 5: Deploy Contract
info "Deploying contract..."
bash script/deploy.sh || error "Contract deployment failed."

# Step 6: Install Bun (for interaction)
info "Installing Bun..."
curl -fsSL https://bun.sh/install | bash || error "Failed to install Bun"
export PATH="$HOME/.bun/bin:$PATH"
success "Bun installed."

# Step 7: Interact with the deployed contract
info "Setting up contract interaction..."
cd "$HOME/try-devnet/packages/cli/" || error "Failed to navigate to CLI directory"
bun install || error "Failed to install dependencies"

info "Running contract transaction script..."
bash script/transact.sh || error "Transaction execution failed."

success "Seismic Devnet contract deployed and interacted successfully!"
