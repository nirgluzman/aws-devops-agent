"""Restore an S3 bucket policy after fault injection.

Restores from the saved backup file, or removes the FaultInjectionDeny
statement by Sid if no backup exists.
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
    parser = argparse.ArgumentParser(description="Restore S3 bucket policy after fault injection")
    parser.add_argument("--bucket-name", required=True, help="Target S3 bucket name")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    backup = _backup_path(args.bucket_name)

    if backup.exists():
        # Restore from saved file
        policy = json.loads(backup.read_text())
        if policy.get("Statement"):
            s3.put_bucket_policy(Bucket=args.bucket_name, Policy=json.dumps(policy))
            print(f"Policy restored from {backup}")
        else:
            s3.delete_bucket_policy(Bucket=args.bucket_name)
            print(f"Original had no statements; bucket policy deleted")
        backup.unlink()
        print(f"Backup file {backup} removed")
    else:
        # No backup — remove FaultInjectionDeny by Sid
        print(f"No backup file found; removing {DENY_SID} statement by Sid")
        try:
            current = json.loads(s3.get_bucket_policy(Bucket=args.bucket_name)["Policy"])
        except s3.exceptions.from_code("NoSuchBucketPolicy"):
            print("No bucket policy exists; nothing to restore")
            return

        remaining = [s for s in current.get("Statement", []) if s.get("Sid") != DENY_SID]

        if not remaining:
            s3.delete_bucket_policy(Bucket=args.bucket_name)
            print(f"FaultInjectionDeny was the only statement; bucket policy deleted")
        else:
            current["Statement"] = remaining
            s3.put_bucket_policy(Bucket=args.bucket_name, Policy=json.dumps(current))
            print(f"FaultInjectionDeny statement removed; policy updated")


if __name__ == "__main__":
    main()
