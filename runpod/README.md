# happy_tentacle's LoRA_Easy_Training_Scripts container

Use un runpod.io: https://runpod.io/console/deploy?template=ioyal6hxh1&ref=1hqcphx3

Source on GitHub: https://github.com/happy-tentacle/sd-training-tools/tree/main/runpod

Based on the standard `runpod/kasm-docker:cuda11` image and extended to have LoRA_Easy_Training_Scripts preinstalled on it, which is launched on pod startup.

All scripts and downloaded files are placed under `/home/ht/training`.

## Environment variables

- `HT_CHECKPOINT_URL`: Checkpoint url to download upon pod startup. If not specified, you will be prompted for a checkpoint to download (which can be skipped).
- `HT_RUNPODCTL_RECEIVE`: Start `runpodctl receive` with the given code upon pod startup.

## Build Docker images

Image with installation of LoRA_Easy_Training_Scripts on pod startup:
```shell
docker build -t happytentacle/ht-runpod-lora-easy-training-scripts:0.2 .
```

Image with LoRA_Easy_Training_Scripts preinstalled:
```shell
docker build -t happytentacle/ht-runpod-lora-easy-training-scripts:preinstalled-0.2 -f Dockerfile-preinstalled .
```