from dotenv import load_dotenv
import runpod
import os
import argparse
import requests
import time

parser = argparse.ArgumentParser(
    prog="terminate-runpod-after-training",
    description="Terminates a pod on runpod.io after training has stopped",
)

parser.add_argument(
    "--pod-name",
    dest="pod_name",
    default="ht-lora-easy-training-scripts",
)
parser.add_argument(
    "--wait-for-training",
    dest="wait_for_training",
    action="store_true",
    help="Wait for training to start before terminating pod",
    default=False,
)
parser.add_argument(
    "--terminate-on-error",
    dest="terminate_on_error",
    action="store_true",
    help="Terminate pod if training status cannot be retrieved",
    default=False,
)

args = parser.parse_args()

pod_name: str = args.pod_name
terminate_on_error: bool = args.terminate_on_error
wait_for_training: bool = args.wait_for_training

load_dotenv()

runpod.api_key = os.getenv("RUNPOD_API_KEY")

if __name__ == "__main__":
    pods: list[dict] = runpod.get_pods()
    pods_to_terminate = [pod for pod in pods if pod["name"] == pod_name]
    pod_to_terminate = pods_to_terminate[0] if len(pods_to_terminate) > 0 else None
    if not pod_to_terminate:
        print(f"Pod with name {pod_name} not found")
        exit(1)

    pod_id = pod_to_terminate["id"]
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

        if responded:
            # Make sure traning status is false for two consecutive calls
            # to avoid terminating pod too early
            if (
                prev_is_training is not None
                and not is_training
                and not prev_is_training
                and (not wait_for_training or training_started)
            ):
                print("Training stopped, terminating pod")
                runpod.terminate_pod(pod_id)
                break
            else:
                prev_is_training = is_training
                if is_training:
                    print("Training in progress")
                else:
                    print(
                        "Training stopped, waiting for one more iteration before terminating pod"
                    )

            if wait_for_training and not training_started:
                print("Waiting for training to start")
        else:
            if terminate_on_error:
                print("Training status could not be retrieved, terminating pod")
                runpod.terminate_pod(pod_id)
                exit(1)

            error_count += 1
            prev_is_training = None
            if error_count > 10:
                print("Failed to get training status 10 times in a row, aborting")
                break

        time.sleep(10)
