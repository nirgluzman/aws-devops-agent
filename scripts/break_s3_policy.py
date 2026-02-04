"""Inject a fault by adding an explicit Deny to an S3 bucket policy.

Appends a FaultInjectionDeny statement that blocks s3:GetObject, s3:PutObject,
and s3:ListBucket for the specified Lambda execution role.
"""

import argparse
import json
import pathlib

import boto3

DENY_SID = "FaultInjectionDeny"
SCRIPT_DIR = pathlib.Path(__file__).parent


def _backup_path(bucket: str) -> pathlib.Path:
    return SCRIPT_DIR / f".original_policy_{bucket}.json"


def main() -> None:
    parser = argparse.ArgumentParser(description="Inject S3 bucket policy fault")
    parser.add_argument("--bucket-name", required=True, help="Target S3 bucket name")
    parser.add_argument("--lambda-role-arn", required=True, help="Lambda execution role ARN to deny")
    args = parser.parse_args()

    s3 = boto3.client("s3")

    # 1. Read current policy (or empty)
    try:
        current = json.loads(s3.get_bucket_policy(Bucket=args.bucket_name)["Policy"])
    except s3.exceptions.from_code("NoSuchBucketPolicy"):
        current = {"Version": "2012-10-17", "Statement": []}

    # 2. Save original
    backup = _backup_path(args.bucket_name)
    backup.write_text(json.dumps(current, indent=2))
    print(f"Original policy saved to {backup}")

    # 3. Append deny statement
    deny_statement = {
        "Sid": DENY_SID,
        "Effect": "Deny",
        "Principal": {"AWS": args.lambda_role_arn},
        "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        "Resource": [
            f"arn:aws:s3:::{args.bucket_name}",
            f"arn:aws:s3:::{args.bucket_name}/*",
        ],
    }

    # Remove any existing fault injection statement first
    current["Statement"] = [s for s in current.get("Statement", []) if s.get("Sid") != DENY_SID]
    current["Statement"].append(deny_statement)

    # 4. Apply
    s3.put_bucket_policy(Bucket=args.bucket_name, Policy=json.dumps(current))
    print(f"Fault injected: {DENY_SID} added to {args.bucket_name}")


if __name__ == "__main__":
    main()
