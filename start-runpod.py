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
    "--image-name",
    dest="image_name",
    default="happytentacle/ht-runpod-lora-easy-training-scripts:preinstalled-0.2",
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
    "--terminate",
    dest="terminate",
    action="store_true",
    help="Terminate existing pod of the same name if present",
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

args = parser.parse_args()

pod_name: str = args.pod_name
image_name: str = args.image_name
runpodctl_receive: str = args.runpodctl_receive
runpodctl_unzip: bool = args.runpodctl_unzip
checkpoint_url: str = args.checkpoint_url
terminate: bool = args.terminate
keep_existing: bool = args.keep_existing
gpu: str = args.gpu
ssh_key: str = args.ssh_key
use_wsl: bool = args.use_wsl
rsync_from: str = args.rsync_from

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")


def transfer_files_from_pod(ssh_public_port, ip):
    print("Transfering files local folder to pod")

    if not ssh_key:
        print("SSH key not specified via --ssh-key, cannot transfer files")
        return

    command_prefix = "wsl " if use_wsl else ""

    os.system(
        f"{command_prefix}rsync -avzP -e 'ssh -p {ssh_public_port} -i {ssh_key}' "
        f"{rsync_from} kasm-user@{ip}:/home/ht/training/"
    )


if __name__ == "__main__":
    pods: list[dict] = runpod.get_pods()
    existing_pods = [pod for pod in pods if pod["name"] == pod_name]

    if terminate:
        for pod in existing_pods:
            pod_id = pod["id"]
            runpod.terminate_pod(pod_id)
            print(f"Terminated pod with id {pod_id}")

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
                    "VNC_PW": "password",
                    "HT_RUNPODCTL_RECEIVE": runpodctl_receive,
                    "HT_CHECKPOINT_URL": checkpoint_url,
                    "HT_RUNPODCTL_UNZIP": "True" if runpodctl_unzip else "False",
                },
            )
        except Exception as e:
            if str(e).index("No GPU found with the specified ID") >= 0:
                print([gpu["id"] for gpu in runpod.get_gpus()])
                raise

    pod_id = pod["id"]
    pod_url = f"https://kasm_user:password@{pod_id}-6901.proxy.runpod.net/"

    print("Started pod 'ht-lora-easy-training-scripts")
    print("Pod list: https://www.runpod.io/console/pods")
    print(f"Pod id: {pod_id}")
    print("Username: kasm_user")
    print("Password: password")

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

            res = requests.get(pod_url)
            # Wait for both VNC and SSH to be ready
            if res.status_code == 200 and ssh_ports:
                break
            print("Pod is not ready yet, waiting 5 seconds")
        except requests.exceptions.RequestException:
            print("Pod is not ready yet, waiting 5 seconds")

        time.sleep(5)

    ip = ssh_ports[0]["ip"]
    ssh_public_port = ssh_ports[0]["publicPort"]

    print(f"Desktop url: {pod_url}")
    print(f"Public IP: {ip}")

    print(
        f"\nConnect via ssh using:\nssh kasm-user@{ip} -p {ssh_public_port} -i {ssh_key}"
    )
    print(
        "\nTransfer files from local machine to pod using:\n"
        f"rsync -avzP -e ssh -p {ssh_public_port}' -i {ssh_key} "
        f"kasm-user@{ip}:/home/ht/training /path/to/local/file"
    )
    print(
        "\nTransfer files from pod to local machine using:\n"
        f"rsync -avzP -e ssh -p {ssh_public_port}' -i {ssh_key} "
        "--exclude='LoRA_Easy_Training_Scripts' --include='/*/' --include='/*/**' --exclude='*' "
        f"kasm-user@{ip}:/home/ht/training /path/to/local/file"
    )
    print(
        "\nTransfer files and terminate pod after training using:\n"
        "python .\\runpod-wait-for-training.py --wait-for-training-start --continuous-rsync "
        "--terminate --use-wsl --rsync-to /path/to/local/file"
    )

    if rsync_from:
        transfer_files_from_pod(ssh_public_port, ip)
