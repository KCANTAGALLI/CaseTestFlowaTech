import json
import os
import boto3

ec2 = boto3.client("ec2")

INSTANCE_ID = os.environ["INSTANCE_ID"]


def handler(event, context):
    action = (event.get("action") or "").lower()
    if action not in ("start", "stop"):
        raise ValueError(f"action inválida: {action}")

    print(f"{action} instance {INSTANCE_ID}")

    if action == "start":
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
    else:
        ec2.stop_instances(InstanceIds=[INSTANCE_ID])

    return {
        "statusCode": 200,
        "body": json.dumps({"action": action, "instanceId": INSTANCE_ID}),
    }
