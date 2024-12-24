#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd /home/ht/training

echo "Setting up ssh service"

mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "$PUBLIC_KEY" > ~/.ssh/authorized_keys
chmod 700 ~/.ssh/authorized_keys
sudo chmod 777 /etc/ssh/sshd_config
sudo printf "PasswordAuthentication no\nStrictModes no" >> /etc/ssh/sshd_config
sudo chmod 700 /etc/ssh/sshd_config
sudo service ssh start

if [ "${HT_RUNPODCTL_RECEIVE}" != "" ]; then 
    echo "Retrieving remote file via runpodctl"

    runpodctl receive "$HT_RUNPODCTL_RECEIVE"

    if [ "${HT_RUNPODCTL_UNZIP}" == "True" ]; then 
        unzip *.zip
    fi
fi

source "$SCRIPT_DIR/select-checkpoint.sh"

echo "Launching LoRA_Easy_Training_Scripts"

cd /home/ht/training/LoRA_Easy_Training_Scripts
source "./run.sh" | tee run_out.txt