from dotenv import load_dotenv
import runpod
import os
import argparse
import time
import requests

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

args = parser.parse_args()

pod_name: str = args.pod_name
image_name: str = args.image_name
runpodctl_receive: str = args.runpodctl_receive
runpodctl_unzip: bool = args.runpodctl_unzip
checkpoint_url: str = args.checkpoint_url
terminate: bool = args.terminate

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

if __name__ == "__main__":
    if terminate:
        pods: list[dict] = runpod.get_pods()
        pod_ids_to_terminate = [pod["id"] for pod in pods if pod["name"] == pod_name]
        for pod_id in pod_ids_to_terminate:
            runpod.terminate_pod(pod_ids_to_terminate[0])
            print(f"Terminated pod with id {pod_ids_to_terminate[0]}")

    pod = runpod.create_pod(
        name=pod_name,
        image_name=image_name,
        gpu_type_id="NVIDIA RTX 6000 Ada Generation",
        volume_in_gb=0,
        container_disk_in_gb=60,
        support_public_ip=True,
        # Port 6901 is for VNC
        # Port 8000 is for the LoRA_Easy_Training_Scripts backend API
        ports="6901/http,8000/http",
        env={
            "VNC_PW": "password",
            "HT_RUNPODCTL_RECEIVE": runpodctl_receive,
            "HT_CHECKPOINT_URL": checkpoint_url,
            "HT_RUNPODCTL_UNZIP": "True" if runpodctl_unzip else "False",
        },
    )
    pod_id = pod["id"]
    pod_url = f"https://kasm_user:password@{pod_id}-6901.proxy.runpod.net/"

    print("Started pod 'ht-lora-easy-training-scripts")
    print("Pod list: https://www.runpod.io/console/pods")
    print(f"Pod id: {pod_id}")
    print("Username: kasm_user")
    print("Password: password")

    while True:
        try:
            res = requests.get(pod_url)
            if res.status_code == 200:
                break
            print("Pod is not ready yet, waiting 1 second")
        except requests.exceptions.RequestException:
            print("Pod is not ready yet, waiting 1 second")
        time.sleep(1)

    print(f"Desktop url: {pod_url}")
