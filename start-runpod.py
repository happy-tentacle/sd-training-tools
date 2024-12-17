from dotenv import load_dotenv
import runpod
import os
import argparse
import time
import requests
import webbrowser

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
checkpoint_url: str = args.checkpoint_url
terminate: bool = args.terminate

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

if __name__ == "__main__":
    if terminate:
        pods: list[dict] = runpod.get_pods()
        pod_id_to_terminate = next(pod["id"] for pod in pods if pod["name"] == pod_name)
        if pod_id_to_terminate:
            runpod.terminate_pod(pod_id_to_terminate)
            print(f"Terminated pod with id {pod_id_to_terminate}")

    pod = runpod.create_pod(
        name=pod_name,
        image_name=image_name,
        gpu_type_id="NVIDIA RTX 6000 Ada Generation",
        volume_in_gb=0,
        container_disk_in_gb=60,
        support_public_ip=True,
        ports="6901/http",
        env={
            "VNC_PW": "password",
            "HT_RUNPODCTL_RECEIVE": runpodctl_receive,
            "HT_CHECKPOINT_URL": checkpoint_url,
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
    webbrowser.open(pod_id)
