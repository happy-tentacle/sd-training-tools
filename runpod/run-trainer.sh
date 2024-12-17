#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd /home/ht/training

if [ x"${HT_RUNPODCTL_RECEIVE}" != "x" ]; then 
    runpodctl receive "$HT_RUNPODCTL_RECEIVE"
fi

source "$SCRIPT_DIR/select-checkpoint.sh"

echo "Launching LoRA_Easy_Training_Scripts"

cd /home/ht/training/LoRA_Easy_Training_Scripts
source "./run.sh"