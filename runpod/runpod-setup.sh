#!/bin/bash
set -e

SECONDS=0

echo "Creating training home folder"

sudo mkdir -p /home/ht/training
sudo chown -R kasm-user /home/ht/training
cd /home/ht/training

echo "Downloading ponyDiffusionV6XL_v6StartWithThisOne.safetensors"

curl -O -L https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors

echo "Installing dependencies"

sudo apt-get update

# To send files via zip later on
sudo apt-get -y install zip

# Install Python 3.11
sudo apt-get -y install python3.11
sudo apt-get -y install python3.11-venv

# Dependencies for QT (which LoRA_Easy_Training_Scripts uses)
sudo apt-get -y install build-essential
sudo apt-get -y install libx11-xcb-dev libglu1-mesa-dev
sudo apt-get -y install libxcb-cursor0

echo "Installing LoRA_Easy_Training_Scripts"

# Checkout and install LoRA_Easy_Training_Scripts
git clone https://github.com/derrian-distro/LoRA_Easy_Training_Scripts
cd LoRA_Easy_Training_Scripts
echo -e "y" | python3.11 install.py

duration=$SECONDS
echo "Setup completed in $((duration / 60)) minutes and $((duration % 60)) seconds"

echo "Launching LoRA_Easy_Training_Scripts"

source run.sh