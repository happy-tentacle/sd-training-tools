# Running LoRA Easy Training Scripts on runpod.io

## (Recommended) Configure public ssh key

Configure public ssh key to connect remotely via ssh using `ssh-keygen`
Set content of `.pub` file into [Settings](https://www.runpod.io/console/user/settings) > SSH Public Keys

## Create Pod

Template: RunPod Desktop
Edit template and set the following values
- Temp storage: 60 GB
- Volume storage: 0 GB

With RTX 4090, network dim 8, batch size 3, gradient checkpointing enabled: 1.3s/it (30 mins for 1400 steps)
With RTX 6000 Ada, network dim 8, batch size 3, gradient checkpointing disabled: 1.1s/it (23 mins for 1400 steps)

Click "Connect to HTTP Service [Port 6901]" to open remote desktop session via KasmVNC
Default username: kasm_user
Default password: password

NOTE: If the Desktop suddently becomes empty, just refresh the current tab

## Install Lora Easy Training Scripts on RunPod

```shell
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

# Checkout and install LoRA_Easy_Training_Scripts
git clone https://github.com/derrian-distro/LoRA_Easy_Training_Scripts
cd LoRA_Easy_Training_Scripts
python3.11 install.py
source run.sh
```

## Prepare user folder

In RunPod terminal:
```shell
sudo mkdir /home/ht/training
sudo chown -R kasm-user /home/ht/training
cd /home/ht/training

curl -O -L https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors
```

## Copy files from local to server

First, [install runpodctl](https://docs.runpod.io/runpodctl/install-runpodctl) locally

In local terminal:
```shell
runpodctlconfig --apiKey <api-key-from-user-settings> # If running for the first time

# zip folder
# runpodctl can do it automatically but it sometimes fails to unzip properly and produces an empty file
tar acvf folder.zip <path-of-folder-to-zip> # without slashes at the beginning or end of the path

runpodctl send <path-to-local-file-or-folder>
```

In RunPod terminal:
```shell
runpodctl receive <code-from-local-server>
```

## Copy files from server to local

In RunPod terminal:
```shell
# zip current folder
# runpodctl can do it automatically but it sometimes fails to unzip properly and produces an empty file
zip -r folder.zip .

runpodctl send <path-to-file-or-folder-on-runpod>
```

In local terminal:
```shell
runpodctl receive <code-from-runpod>
```

## Watching GPU usage

```shell
watch -n 1 nvidia-smi
```

## References

- https://blog.runpod.io/gpu-accelerated-virtual-desktop-on-runpod/
- https://www.digitalocean.com/community/tutorials/workflow-downloading-files-curl
- https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server
- https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL
- https://wiki.qt.io/Qt5_dependencies
- https://docs.runpod.io/pods/storage/transfer-files#transferring-with-runpodctl
- HTTPConnectionPool error: https://github.com/derrian-distro/LoRA_Easy_Training_Scripts/issues/231