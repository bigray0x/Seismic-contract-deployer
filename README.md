# Seismic Devnet Smart Contract Deployment Script

This script automates the setup, funding, deployment, and interaction with a smart contract on Seismic Devnet.

## 🚀 Features
✅ Checks and installs missing dependencies  
✅ Requests test ETH from the Seismic faucet  
✅ Waits for funds before proceeding with deployment  
✅ Deploys the contract automatically  
✅ Interacts with the extended contract  

## 🛠️ Requirements
- Ubuntu 20.04+ or a compatible Linux system  
- At least **8GB RAM**  
- At least **5GB free disk space**  

## 📦 Installation
Clone the repository:
```sh
git clone https://github.com/yourusername/Seismic-contract-deployer.git
cd Seismic-contract-deployer

next,

chmod +x deploy_contract.sh

then,

./deploy_contract.sh

• The script will ask for your wallet address and validate it.
• It will claim test ETH and wait until the funds arrive before deploying.
• After deployment, it will interact with the extended contract.
