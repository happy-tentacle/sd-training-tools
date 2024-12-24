from dotenv import load_dotenv
import runpod
import os
import argparse
import time
import requests
import subprocess
import logging
import sys
import signal
import re
from rich.logging import RichHandler

# Example usage
# python .\start-runpod.py --terminate --checkpoint-url "https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors" --use-wsl --rsync-from "/mnt/t/stablediffusion/training/transfer"

logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser(
    prog="start-runpod",
    description="Starts a pod on runpod.io",
    formatter_class=argparse.ArgumentDefaultsHelpFormatter,
)

# Remaining letters: "ohjlv"
parser.add_argument(
    "-n",
    "--pod-name",
    dest="pod_name",
    help="Name of the pod to get or create",
    default="ht-lora-easy-training-scripts",
)
parser.add_argument(
    "-p",
    "--password",
    dest="password",
    help="VNC password to use",
    default="password",
)
parser.add_argument(
    "-i",
    "--image-name",
    dest="image_name",
    help="Container image name to use",
    default="happytentacle/ht-runpod-lora-easy-training-scripts:preinstalled-0.3",
)
parser.add_argument(
    "-g",
    "--gpu",
    dest="gpu",
    help="GPU id to use",
    default="NVIDIA RTX 6000 Ada Generation",
)
parser.add_argument(
    "--runpodctl-receive",
    help="Code to automatically pass to runpodctl receive on pod startup",
    dest="runpodctl_receive",
)
parser.add_argument(
    "--runpodctl-unzip",
    dest="runpodctl_unzip",
    action="store_true",
    help="If True, will unzip the file received via --runpodctl-receive",
    default=False,
)
parser.add_argument(
    "-u",
    "--checkpoint-url",
    help="Url of checkpoint to download on pod startup",
    dest="checkpoint_url",
)
parser.add_argument(
    "-x",
    "--terminate-existing",
    dest="terminate_existing",
    action="store_true",
    help="Terminate existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "-r",
    "--restart-existing",
    dest="restart_existing",
    action="store_true",
    help="Restart existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "-z",
    "--keep-existing",
    dest="keep_existing",
    action="store_true",
    help="Keep existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "-k",
    "--ssh-key",
    dest="ssh_key",
    help="Path to public SSH key",
    default="~/.ssh/id_ed25519",
)
parser.add_argument(
    "-f",
    "--rsync-from",
    dest="rsync_from",
    help="Run rsync to copy local files to pod",
)
parser.add_argument(
    "-w",
    "--use-wsl",
    dest="use_wsl",
    action="store_true",
    help="Use WSL to run rsync",
    default=False,
)
parser.add_argument(
    "-t",
    "--rsync-to",
    dest="rsync_to",
    help="Run rsync to copy pod files to specified local folder",
)
parser.add_argument(
    "-m",
    "--monitor-training",
    dest="monitor_training",
    action="store_true",
    help="Monitor training continuously",
    default=False,
)
parser.add_argument(
    "-c",
    "--continuous-rsync",
    dest="continuous_rsync",
    action="store_true",
    help="Run rsync every iteration",
    default=False,
)
parser.add_argument(
    "-e",
    "--terminate-on-error",
    dest="terminate_on_error",
    action="store_true",
    help="Terminate pod if training status cannot be retrieved",
    default=False,
)
parser.add_argument(
    "-q",
    "--terminate-after-training",
    dest="terminate_after_training",
    action="store_true",
    help="Terminate pod when training has completed",
    default=False,
)
parser.add_argument(
    "-y",
    "--immediate",
    dest="immediate",
    action="store_true",
    help="Run commands immediately instead of waiting for training to complete",
    default=False,
)
parser.add_argument(
    "-d",
    "--wait-for-sec",
    dest="wait_for_sec",
    help="Wait for X additional seconds before running post-training commands",
    default="0",
)
parser.add_argument(
    "-s",
    "--iter-sec",
    dest="iter_sec",
    help="Wait for X seconds before each training status check iteration",
    default="10",
)
parser.add_argument(
    "-a",
    "--wait-for-training-start",
    dest="wait_for_training_start",
    action="store_true",
    help="Wait for training to start before terminating pod",
    default=False,
)
parser.add_argument(
    "-b",
    "--submit-training-files",
    dest="submit_training_files",
    action="store_true",
    help="Submit training files (must be named 'backend_input.json' and placed under /home/ht/training in the pod)",
    default=False,
)

args = parser.parse_args()

pod_name: str = args.pod_name
password: str = args.password
image_name: str = args.image_name
runpodctl_receive: str = args.runpodctl_receive
runpodctl_unzip: bool = args.runpodctl_unzip
checkpoint_url: str = args.checkpoint_url
terminate_existing: bool = args.terminate_existing
restart_existing: bool = args.restart_existing
keep_existing: bool = args.keep_existing
terminate_after_training: bool = args.terminate_after_training
gpu: str = args.gpu
ssh_key: str = args.ssh_key
use_wsl: bool = args.use_wsl
rsync_from: str = args.rsync_from
monitor_training: bool = args.monitor_training
rsync_to: str = args.rsync_to
terminate_after_training: bool = args.terminate_after_training
immediate: bool = args.immediate
terminate_on_error: bool = args.terminate_on_error
continuous_rsync: bool = args.continuous_rsync
wait_for_training_start: bool = args.wait_for_training_start
wait_for_sec: int = int(args.wait_for_sec)
iter_sec: int = int(args.iter_sec)
submit_training_files: bool = args.submit_training_files

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

command_prefix = "wsl " if use_wsl else ""

epoch_progress_regex = re.compile("epoch ([0-9]+)/([0-9]+)")


def transfer_files_to_pod(ssh_public_port: int, ip: str):
    logger.info("Transfering files local folder to pod")

    if not ssh_key:
        logger.info("SSH key not specified via --ssh-key, cannot transfer files")
        return

    os.system(
        f"{command_prefix}rsync -avzP -e 'ssh -p {ssh_public_port} -i {ssh_key} -o \"StrictHostKeyChecking=no\"' "
        f"{rsync_from} kasm-user@{ip}:/home/ht/training/"
    )


def transfer_files_from_pod(ssh_public_port: int, ip: str):
    logger.info("Transfering files from pod to local folder")

    if not ssh_key:
        logger.error("SSH key not specified via --ssh-key, cannot transfer files")
        return

    # Include all subfolders of /home/ht/training
    # Except for LoRA_Easy_Training_Scripts
    os.system(
        f"{command_prefix}rsync -avzP -e 'ssh -p {ssh_public_port} -i {ssh_key} -o \"StrictHostKeyChecking=no\"' "
        "--exclude='LoRA_Easy_Training_Scripts' --include='/*/' --include='/*/**' --exclude='*' "
        f"kasm-user@{ip}:/home/ht/training/ {rsync_to}"
    )


def terminate_pod(pod_id: str):
    logger.warning(f"Terminating pod with id {pod_id}")
    runpod.terminate_pod(pod_id)


def restart_pod(pod_id: str):
    logger.warning(f"Restarting pod with id {pod_id}")
    runpod.stop_pod(pod_id)
    runpod.resume_pod(pod_id)


def wait_for_training(pod: dict, ssh_public_port: int, ip: str):
    pod_id = pod["id"]
    pod_training_url = f"https://{pod_id}-8000.proxy.runpod.net/"

    prev_is_training: bool | None = None
    training_started: bool = False

    training_input_files = (
        get_training_input_files(ssh_public_port, ip) if submit_training_files else []
    )

    if submit_training_files and not training_input_files and terminate_after_training:
        logger.error("Found no training files, aborting")
        if terminate_on_error:
            terminate_pod(pod_id)
        exit(1)

    while True:
        responded = False
        try:
            res = requests.get(f"{pod_training_url}/is_training")
            if res.status_code == 200:
                res_json = res.json()
                is_training: bool = res_json["training"]
                responded = True

                if is_training:
                    training_started = True
            else:
                logger.warning(
                    f"Error retrieving training status, got status code {res.status_code}"
                )

        except requests.exceptions.RequestException as e:
            logger.warning(f"Error retrieving training status: {e}")

        if responded or immediate:
            # Make sure traning status is false for two consecutive calls
            # to avoid terminating pod too early
            if (
                immediate
                or prev_is_training is not None
                and not is_training
                and not prev_is_training
                and (not wait_for_training_start or training_started)
            ):
                if wait_for_sec:
                    logger.info(
                        f"Waiting for {wait_for_sec} seconds before running commands"
                    )
                    time.sleep(wait_for_sec)

                logger.info("Training stopped")

                if rsync_to:
                    transfer_files_from_pod(ssh_public_port, ip)

                if not is_training and len(training_input_files):
                    training_file = training_input_files.pop()
                    submit_training_input_file(ssh_public_port, ip, training_file)
                else:
                    if terminate_after_training:
                        terminate_pod(pod_id)
                    break
            else:
                prev_is_training = is_training
                if is_training:
                    print_training_progress(ssh_public_port, ip)
                elif not wait_for_training_start or training_started:
                    logger.info(
                        "Training stopped, waiting for one more iteration before running commands"
                    )

                if continuous_rsync:
                    transfer_files_from_pod(ssh_public_port, ip)

            if wait_for_training_start and not training_started:
                logger.info("Waiting for training to start")
        else:
            if terminate_on_error:
                logger.error("Training status could not be retrieved")
                terminate_pod(pod_id)
                exit(1)

            prev_is_training = None

        time.sleep(iter_sec)


def get_or_create_pod():
    pods: list[dict] = runpod.get_pods()
    existing_pods = [pod for pod in pods if pod["name"] == pod_name]

    if terminate_existing:
        for pod in existing_pods:
            terminate_pod(pod["id"])
    elif restart_existing:
        for pod in existing_pods:
            restart_pod(pod["id"])

    if keep_existing and existing_pods:
        pod = existing_pods[0]
        pod_id = pod["id"]
        logger.info(f"Reusing pod with id {pod_id}")
    else:
        try:
            pod = runpod.create_pod(
                name=pod_name,
                image_name=image_name,
                gpu_type_id=gpu,
                volume_in_gb=0,
                container_disk_in_gb=60,
                support_public_ip=True,
                # Port 6901 is for VNC
                # Port 8000 is for the LoRA_Easy_Training_Scripts backend API
                ports="6901/http,8000/http,22/tcp",
                # See also: https://docs.runpod.io/pods/references/environment-variables
                env={
                    "VNC_PW": password,
                    "HT_RUNPODCTL_RECEIVE": (
                        runpodctl_receive if runpodctl_receive else ""
                    ),
                    "HT_CHECKPOINT_URL": checkpoint_url if checkpoint_url else "",
                    "HT_RUNPODCTL_UNZIP": "True" if runpodctl_unzip else "False",
                },
            )
            pod_id = pod["id"]
            logger.info(f"Created pod with id {pod_id}")
        except Exception as e:
            if str(e).index("No GPU found with the specified ID") >= 0:
                logger.info([gpu["id"] for gpu in runpod.get_gpus()])
                raise
    return pod


def get_training_input_files(ssh_public_port: int, ip: str):
    logger.info("Getting list of input files to submit for training")

    command = list()
    command.extend([command_prefix] if command_prefix else [])
    command.extend(
        [
            "ssh",
            f"kasm-user@{ip}",
            "-p",
            f"{ssh_public_port}",
            "-i",
            f"{ssh_key}",
            "find",
            "/home/ht/training",
            "-name",
            "backend_input.json",
        ]
    )
    logger.info(" ".join(command))

    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error(
            "Failed to get list of backend_input.json files to submit for training, "
            f"got return code {result.returncode}"
        )
        exit(1)

    input_files = [line.strip() for line in result.stdout.split()]
    logger.info(
        f"Found {len(input_files)} input files to submit for training:\n{input_files}"
    )

    if not input_files:
        logger.error("No training files found")

    return input_files


def submit_training_input_file(ssh_public_port: int, ip: str, file_path: str):
    logger.info(f"Validating training file {file_path}")

    command = list()
    command.extend([command_prefix] if command_prefix else [])
    command.extend(
        [
            "ssh",
            f"kasm-user@{ip}",
            "-p",
            f"{ssh_public_port}",
            "-i",
            f"{ssh_key}",
            f"jq '.args.general_args.gradient_checkpointing=\"false\"' {file_path} | "
            # f"cat {file_path} | "
            'curl --fail --no-progress-meter -X POST -H "Content-Type: application/json" '
            '--data @- "http://localhost:8000/validate"',
        ]
    )
    logger.info(" ".join(command))

    result = subprocess.run(command, check=True)
    if result.returncode != 0:
        logger.error(
            f"Failed to validate training file, got return code {result.returncode}"
        )
        exit(1)

    logger.info(f"Starting training for file {file_path}")

    command = list()
    command.extend([command_prefix] if command_prefix else [])
    command.extend(
        [
            "ssh",
            f"kasm-user@{ip}",
            "-p",
            f"{ssh_public_port}",
            "-i",
            f"{ssh_key}",
            'curl --fail --no-progress-meter "http://localhost:8000/train?train_mode=lora&sdxl=True"',
        ]
    )
    logger.info(" ".join(command))

    result = subprocess.run(command, check=True)
    if result.returncode != 0:
        logger.error(f"Failed to start training, got return code {result.returncode}")
        exit(1)


def print_training_progress(ssh_public_port: int, ip: str):
    command = list()
    command.extend([command_prefix] if command_prefix else [])
    command.extend(
        [
            "ssh",
            f"kasm-user@{ip}",
            "-p",
            f"{ssh_public_port}",
            "-i",
            f"{ssh_key}",
            'tac /home/ht/training/LoRA_Easy_Training_Scripts/run_out.txt | grep -E -m1 "epoch ([0-9]+)/([0-9]+)"',
        ]
    )
    logger.info(" ".join(command))

    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning(
            f"Training still ongoing but failed to retrieve progress, got return code {result.returncode}"
        )
        return

    match = epoch_progress_regex.search(result.stdout)
    if not match:
        logger.warning("Failed to parse training progress")
        return

    epoch_current = match.group(1)
    epoch_total = match.group(2)
    logger.info(f"Training at epoch {epoch_current}/{epoch_total}")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(message)s",
        datefmt="%H:%M:%S",
        handlers=[RichHandler()],
        force=True,
    )

    signal.signal(signal.SIGINT, lambda sig, frame: sys.exit(1))

    if submit_training_files and wait_for_training_start:
        logger.error(
            "Cannot set both --submit-training-files and --wait-for-training-start"
        )
        exit(1)

    pod = get_or_create_pod()
    pod_id: str = pod["id"]
    pod_vnc_url = f"https://kasm_user:{password}@{pod_id}-6901.proxy.runpod.net/"
    pod_training_url = f"https://{pod_id}-8000.proxy.runpod.net/"

    logger.info("Pod list: https://www.runpod.io/console/pods")
    logger.info(f"Pod id: {pod_id}")
    logger.info("Username: kasm_user")
    logger.info(f"Password: {password}")

    while True:
        try:
            # Refresh pod information
            pod = runpod.get_pod(pod_id)
            ssh_ports = []
            if pod["runtime"] and pod["runtime"]["ports"]:
                ssh_ports = [
                    port
                    for port in pod["runtime"]["ports"]
                    if port["privatePort"] == 22
                ]

            res = requests.get(pod_vnc_url)
            # Wait for both VNC and SSH to be ready
            if res.status_code == 200 and ssh_ports:
                break
            logger.info("Pod is not ready yet, waiting 5 seconds")
        except requests.exceptions.RequestException:
            logger.info("Pod is not ready yet, waiting 5 seconds")

        time.sleep(5)

    ip: str = ssh_ports[0]["ip"]
    ssh_public_port: int = ssh_ports[0]["publicPort"]

    logger.info(f"Desktop url: {pod_vnc_url}")
    logger.info(f"Public IP: {ip}")

    logger.info(
        "\nTo connect via SSH: "
        f"{command_prefix}ssh kasm-user@{ip} -p {ssh_public_port} -i {ssh_key}"
    )

    logger.info(
        "\nTo watch GPU usage: "
        f"{command_prefix}ssh kasm-user@{ip} -p {ssh_public_port} -i {ssh_key} "
        "-t 'watch -n 1 nvidia-smi'"
    )

    logger.info(
        "\nTo stop training: "
        f"{command_prefix}ssh kasm-user@{ip} -p {ssh_public_port} -i {ssh_key} "
        "-t 'curl http://localhost:8000/stop_training'"
    )

    if rsync_from:
        transfer_files_to_pod(ssh_public_port, ip)

    if monitor_training:
        wait_for_training(pod, ssh_public_port, ip)
