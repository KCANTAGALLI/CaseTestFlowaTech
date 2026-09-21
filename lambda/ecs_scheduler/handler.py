import json
import os
import boto3

ecs = boto3.client("ecs")

CLUSTER = os.environ["ECS_CLUSTER"]
SERVICE = os.environ["ECS_SERVICE"]


def handler(event, context):
    action = (event.get("action") or "").lower()
    if action not in ("start", "stop"):
        raise ValueError(f"action inválida: {action}")

    desired = 1 if action == "start" else 0
    print(f"{action} -> desiredCount={desired} em {CLUSTER}/{SERVICE}")

    ecs.update_service(
        cluster=CLUSTER,
        service=SERVICE,
        desiredCount=desired,
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"action": action, "desiredCount": desired}),
    }
