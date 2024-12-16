from dotenv import load_dotenv
import runpod
import os
import argparse

parser = argparse.ArgumentParser(
    prog="start-runpod",
    description="Starts a pod on runpod.io",
)

parser.add_argument(
    "--image-name",
    dest="image_name",
    default="happytentacle/ht-runpod-lora-easy-training-scripts:0.3",
)

args = parser.parse_args()

image_name: str = args.image_name

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

if __name__ == "__main__":
    pod = runpod.create_pod(
        name="ht-lora-easy-training-scripts",
        image_name=image_name,
        gpu_type_id="NVIDIA RTX 6000 Ada Generation",
        volume_in_gb=0,
        container_disk_in_gb=60,
        support_public_ip=True,
        ports="6901/http",
        env={"VNC_PW": "password"},
    )
    pod_id = pod["id"]

    print("Started pod 'ht-lora-easy-training-scripts")
    print("Pod list: https://www.runpod.io/console/pods")
    print(f"Pod id: {pod_id}")
    print("Username: kasm_user")
    print("Password: password")
    print(f"Desktop url: https://kasm_user:password@{pod_id}-6901.proxy.runpod.net/")
    print("(might take a few seconds to be available)")
