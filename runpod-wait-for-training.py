from dotenv import load_dotenv
import runpod
import os
import argparse
import requests
import time

parser = argparse.ArgumentParser(
    prog="runpod-wait-for-training",
    description="Waits for a training on runpod.io to complete",
)

parser.add_argument(
    "--pod-name",
    dest="pod_name",
    help="Pod name",
    default="ht-lora-easy-training-scripts",
)
parser.add_argument(
    "--wait-for-training-start",
    dest="wait_for_training_start",
    action="store_true",
    help="Wait for training to start before terminating pod",
    default=False,
)
parser.add_argument(
    "--terminate",
    dest="terminate",
    action="store_true",
    help="Terminate pod when training has completed",
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
    "--ssh-key",
    dest="ssh_key",
    help="Path to public SSH key",
    default="~/.ssh/id_ed25519",
)
parser.add_argument(
    "--rsync-to",
    dest="rsync_to",
    help="Run rsync to copy pod files to specified local folder",
    default="",
)
parser.add_argument(
    "--continuous-rsync",
    dest="continuous_rsync",
    action="store_true",
    help="Run rsync every iteration",
    default=False,
)
parser.add_argument(
    "--use-wsl",
    dest="use_wsl",
    action="store_true",
    help="Use WSL to run rsync",
    default=False,
)

args = parser.parse_args()

pod_name: str = args.pod_name
terminate: bool = args.terminate
immediate: bool = args.immediate
terminate_on_error: bool = args.terminate_on_error
use_wsl: bool = args.use_wsl
continuous_rsync: bool = args.continuous_rsync
wait_for_training_start: bool = args.wait_for_training_start
wait_for_sec: int = int(args.wait_for_sec)
iter_sec: int = int(args.iter_sec)
ssh_key: str = args.ssh_key
rsync_to: str = args.rsync_to

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")


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


if __name__ == "__main__":
    pods: list[dict] = runpod.get_pods()
    pods_with_name = [pod for pod in pods if pod["name"] == pod_name]
    pod = pods_with_name[0] if len(pods_with_name) > 0 else None
    if not pod:
        print(f"Pod with name {pod_name} not found")
        exit(1)

    pod_id = pod["id"]
    pod_training_url = f"https://kasm_user:password@{pod_id}-8000.proxy.runpod.net/"

    error_count = 0
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
                error_count = 0

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

                if terminate:
                    terminate_pod(pod_id)
                break
            else:
                prev_is_training = is_training
                if is_training:
                    print("Training in progress")
                else:
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

            error_count += 1
            prev_is_training = None
            if error_count > 10:
                print("Failed to get training status 10 times in a row, aborting")
                break

        time.sleep(iter_sec)
