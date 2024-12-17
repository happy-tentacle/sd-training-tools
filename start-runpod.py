from dotenv import load_dotenv
import runpod
import os
import argparse
import time
import requests

# Example usage
# python .\start-runpod.py --terminate --checkpoint-url "https://huggingface.co/LyliaEngine/Pony_Diffusion_V6_XL/resolve/main/ponyDiffusionV6XL_v6StartWithThisOne.safetensors" --use-wsl --rsync-from "/mnt/t/stablediffusion/training/transfer"

parser = argparse.ArgumentParser(
    prog="start-runpod",
    description="Starts a pod on runpod.io",
)

parser.add_argument(
    "--pod-name",
    dest="pod_name",
    default="ht-lora-easy-training-scripts",
)
parser.add_argument(
    "--password",
    dest="password",
    default="password",
)
parser.add_argument(
    "--image-name",
    dest="image_name",
    default="happytentacle/ht-runpod-lora-easy-training-scripts:preinstalled-0.3",
)
parser.add_argument(
    "--gpu",
    dest="gpu",
    default="NVIDIA RTX 6000 Ada Generation",
)
parser.add_argument(
    "--runpodctl-receive",
    dest="runpodctl_receive",
    default="",
)
parser.add_argument(
    "--runpodctl-unzip",
    dest="runpodctl_unzip",
    action="store_true",
    help="If True, will unzip the file received via --runpodctl-receive",
    default=False,
)
parser.add_argument(
    "--checkpoint-url",
    dest="checkpoint_url",
    default="",
)
parser.add_argument(
    "--terminate-existing",
    dest="terminate_existing",
    action="store_true",
    help="Terminate existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "--restart-existing",
    dest="restart_existing",
    action="store_true",
    help="Restart existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "--keep-existing",
    dest="keep_existing",
    action="store_true",
    help="Keep existing pod of the same name if present",
    default=False,
)
parser.add_argument(
    "--ssh-key",
    dest="ssh_key",
    help="Path to public SSH key",
    default="~/.ssh/id_ed25519",
)
parser.add_argument(
    "--rsync-from",
    dest="rsync_from",
    help="Run rsync to copy local files to pod",
    default="",
)
parser.add_argument(
    "--use-wsl",
    dest="use_wsl",
    action="store_true",
    help="Use WSL to run rsync",
    default=False,
)
parser.add_argument(
    "--rsync-to",
    dest="rsync_to",
    help="Run rsync to copy pod files to specified local folder",
    default="",
)
parser.add_argument(
    "--monitor-training",
    dest="monitor_training",
    action="store_true",
    help="Monitor training continuously",
    default=False,
)
parser.add_argument(
    "--continuous-rsync",
    dest="continuous_rsync",
    action="store_true",
    help="Run rsync every iteration",
    default=False,
)
parser.add_argument(
    "--terminate-on-error",
    dest="terminate_on_error",
    action="store_true",
    help="Terminate pod if training status cannot be retrieved",
    default=False,
)
parser.add_argument(
    "--terminate-after-training",
    dest="terminate_after_training",
    action="store_true",
    help="Terminate pod when training has completed",
    default=False,
)
parser.add_argument(
    "--immediate",
    dest="immediate",
    action="store_true",
    help="Run commands immediately instead of waiting for training to complete",
    default=False,
)
parser.add_argument(
    "--wait-for-sec",
    dest="wait_for_sec",
    help="Wait for X additional seconds before running post-training commands",
    default="0",
)
parser.add_argument(
    "--iter-sec",
    dest="iter_sec",
    help="Wait for X seconds before each training status check iteration",
    default="10",
)
parser.add_argument(
    "--wait-for-training-start",
    dest="wait_for_training_start",
    action="store_true",
    help="Wait for training to start before terminating pod",
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

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

command_prefix = "wsl " if use_wsl else ""


def transfer_files_to_pod(ssh_public_port, ip):
    print("Transfering files local folder to pod")

    if not ssh_key:
        print("SSH key not specified via --ssh-key, cannot transfer files")
        return

    os.system(
        f"{command_prefix}rsync -avzP -e 'ssh -p {ssh_public_port} -i {ssh_key} -o \"StrictHostKeyChecking=no\"' "
        f"{rsync_from} kasm-user@{ip}:/home/ht/training/"
    )


def transfer_files_from_pod(pod):
    print("Transfering files from pod to local folder")

    if not ssh_key:
        print("SSH key not specified via --ssh-key, cannot transfer files")
        return

    ssh_port = [port for port in pod["runtime"]["ports"] if port["privatePort"] == 22]
    if not ssh_port:
        print("SSH port not open, cannot transfer files")
        return

    ssh_public_port = ssh_port[0]["publicPort"]
    ip = ssh_port[0]["ip"]

    command_prefix = "wsl " if use_wsl else ""

    # Include all subfolders of /home/ht/training
    # Except for LoRA_Easy_Training_Scripts
    os.system(
        f"{command_prefix}rsync -avzP -e 'ssh -p {ssh_public_port} -i {ssh_key} -o \"StrictHostKeyChecking=no\"' "
        "--exclude='LoRA_Easy_Training_Scripts' --include='/*/' --include='/*/**' --exclude='*' "
        f"kasm-user@{ip}:/home/ht/training/ {rsync_to}"
    )


def terminate_pod(pod_id):
    print(f"Terminating pod with id {pod_id}")
    runpod.terminate_pod(pod_id)


def restart_pod(pod_id):
    print(f"Restarting pod with id {pod_id}")
    runpod.stop_pod(pod_id)
    runpod.resume_pod(pod_id)


def wait_for_training(pod):
    pod_id = pod["id"]
    pod_training_url = f"https://{pod_id}-8000.proxy.runpod.net/"

    prev_is_training: bool | None = None
    training_started: bool = False

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
                print(
                    f"Error retrieving training status, got status code {res.status_code}"
                )

        except requests.exceptions.RequestException as e:
            print(f"Error retrieving training status: {e}")

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
                    print(f"Waiting for {wait_for_sec} seconds before running commands")
                    time.sleep(wait_for_sec)

                print("Training stopped")

                if rsync_to:
                    transfer_files_from_pod(pod)

                if terminate_after_training:
                    terminate_pod(pod_id)
                break
            else:
                prev_is_training = is_training
                if is_training:
                    print("Training in progress")
                elif not wait_for_training_start or training_started:
                    print(
                        "Training stopped, waiting for one more iteration before running commands"
                    )

                if continuous_rsync:
                    transfer_files_from_pod(pod)

            if wait_for_training_start and not training_started:
                print("Waiting for training to start")
        else:
            if terminate_on_error:
                print("Training status could not be retrieved")
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
                    "HT_RUNPODCTL_RECEIVE": runpodctl_receive,
                    "HT_CHECKPOINT_URL": checkpoint_url,
                    "HT_RUNPODCTL_UNZIP": "True" if runpodctl_unzip else "False",
                },
            )
        except Exception as e:
            if str(e).index("No GPU found with the specified ID") >= 0:
                print([gpu["id"] for gpu in runpod.get_gpus()])
                raise
    return pod


if __name__ == "__main__":
    pod = get_or_create_pod()
    pod_id = pod["id"]
    pod_vnc_url = f"https://kasm_user:{password}@{pod_id}-6901.proxy.runpod.net/"
    pod_training_url = f"https://{pod_id}-8000.proxy.runpod.net/"

    print("Started pod 'ht-lora-easy-training-scripts")
    print("Pod list: https://www.runpod.io/console/pods")
    print(f"Pod id: {pod_id}")
    print("Username: kasm_user")
    print(f"Password: {password}")

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
            print("Pod is not ready yet, waiting 5 seconds")
        except requests.exceptions.RequestException:
            print("Pod is not ready yet, waiting 5 seconds")

        time.sleep(5)

    ip = ssh_ports[0]["ip"]
    ssh_public_port = ssh_ports[0]["publicPort"]

    print(f"Desktop url: {pod_vnc_url}")
    print(f"Public IP: {ip}")

    print(
        "\nConnect via ssh using:\n"
        f"{command_prefix}ssh kasm-user@{ip} -p {ssh_public_port} -i {ssh_key}"
    )

    if rsync_from:
        transfer_files_to_pod(ssh_public_port, ip)

    if monitor_training:
        wait_for_training(pod)
