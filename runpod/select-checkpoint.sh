#!/bin/bash

if [ x"${HT_CHECKPOINT_URL}" == "x" ]; then 
    PS3='Select which checkpoint to download: '
    options=("ponyDiffusionV6XL" "Illustrious-XL-v0.1" "skip")
    select opt in "${options[@]}"
    do
        case $opt in
            "ponyDiffusionV6XL")
                echo "Downloading ponyDiffusionV6XL_v6StartWithThisOne.safetensors from huggingface"
                curl -O -L https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors
                break
                ;;
            "Illustrious-XL-v0.1")
                echo "Downloading Illustrious-XL-v0.1.safetensors from huggingface"
                curl -O -L https://huggingface.co/OnomaAIResearch/Illustrious-xl-early-release-v0/resolve/main/Illustrious-XL-v0.1.safetensors
                break
                ;;
            "skip")
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done
else
    echo "Downloading checkpoint at url $HT_CHECKPOINT_URL"
    curl -O -L "$HT_CHECKPOINT_URL"
fi
