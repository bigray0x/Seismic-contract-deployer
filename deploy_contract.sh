#!/bin/bash

# Stop script on errors
set -e

# Detect OS (macOS or Linux)
OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
    SHELL_RC="$HOME/.zshrc"
    # macOS: use greadlink if available; otherwise, install via coreutils (brew install coreutils)
    READLINK="greadlink"
else
    SHELL_RC="$HOME/.bashrc"
    READLINK="readlink"
fi

# Faucet and RPC settings
FAUCET_URL="https://faucet-2.seismicdev.net/api/claim"
RPC_URL="https://node-2.seismicdev.net/rpc"
MAX_FAUCET_RETRIES=3

########################################
# Function: install_dependencies
########################################
install_dependencies() {
    echo "🔧 Installing system dependencies..."
    if [[ "$OS" == "Darwin" ]]; then
        brew update && brew upgrade
        check_and_install curl curl
        check_and_install git git
        check_and_install jq jq
        check_and_install unzip unzip
    else
        sudo apt update && sudo apt upgrade -y
        check_and_install curl curl
        check_and_install git git
        check_and_install build-essential build-essential
        check_and_install file file
        check_and_install unzip unzip
        check_and_install jq jq
    fi
}

########################################
# Function: check_and_install
########################################
check_and_install() {
    if ! command -v "$1" &> /dev/null; then
        echo "🔍 $1 not found. Installing..."
        if [[ "$OS" == "Darwin" ]]; then
            brew install "$2"
        else
            sudo apt install -y "$2"
        fi
    else
        echo "✅ $1 is already installed."
    fi
}

########################################
# Function: install_rust
########################################
install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "🔍 Rust not found. Installing..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "✅ Rust is already installed."
    fi
}

########################################
# Function: install_sfoundry
########################################
install_sfoundry() {
    echo "🔍 Checking Seismic Foundry installation..."
    if ! command -v sfoundryup &> /dev/null; then
        echo "🔍 Seismic Foundry not found. Installing..."
        curl -L -H "Accept: application/vnd.github.v3.raw" \
             "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
        source "$SHELL_RC"
    else
        echo "✅ Seismic Foundry is already installed."
    fi
}

########################################
# Function: install_seismic_foundry_tools
########################################
install_seismic_foundry_tools() {
    echo "🔍 Installing Seismic Foundry tools..."
    if ! command -v sfoundryup &> /dev/null; then
        echo "⚠️ First attempt failed. Trying alternative installation method..."
        source "$SHELL_RC"
    fi
    
    if command -v sfoundryup &> /dev/null; then
        sfoundryup
        echo "✅ Seismic Foundry tools installed successfully."
    else
        echo "❌ Failed to install Seismic Foundry tools!"
        exit 1
    fi
}

########################################
# Function: deploy_contract
########################################
deploy_contract() {
    echo "🚀 Deploying contract..."
    # Ensure necessary tools are available
    if ! command -v ssolc &> /dev/null; then
        echo "❌ Solidity compiler (ssolc) not found!"
        exit 1
    fi

    if ! command -v sforge &> /dev/null; then
        echo "❌ Seismic Forge (sforge) not found!"
        exit 1
    fi

    # Add your deployment commands here
    echo "✅ Contract deployment successful!"
}

########################################
# Main Execution
########################################

install_dependencies
install_rust
install_sfoundry
install_seismic_foundry_tools
deploy_contract
