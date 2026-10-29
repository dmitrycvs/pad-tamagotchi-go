#!/usr/bin/env python3
"""Emit instance -> public WebSocket URL JSON from running Compose containers.

Only hostnames and published ports are inspected, never container credentials.
Run again after scaling or replacing containers, then reload the gateway config.
"""
import argparse
import json
import re
import subprocess


def command(args):
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if result.returncode:
        raise SystemExit(result.stderr.strip() or "Docker inspection failed")
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-f", "--compose-file", action="append", default=[])
    parser.add_argument("-p", "--project-name")
    parser.add_argument("--service", action="append", default=[])
    parser.add_argument("--public-host", default="localhost")
    parser.add_argument("--scheme", choices=["ws", "wss"], default="ws")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.public_host):
        parser.error("--public-host must be a DNS hostname or IPv4 address")
    compose = ["docker", "compose"]
    for path in args.compose_file:
        compose.extend(["-f", path])
    if args.project_name:
        compose.extend(["-p", args.project_name])
    services = args.service or ["guild-service", "battle-service", "map-service", "monster-raid-service"]
    ids = command(compose + ["ps", "-q", *services]).splitlines()
    urls = {}
    # docker inspect with a template deliberately excludes Config.Env.
    template = '{"instance_id":{{json .Config.Hostname}},"bindings":{{json (index .NetworkSettings.Ports "8080/tcp")}}}'
    for container in ids:
        record = json.loads(command(["docker", "inspect", "--format", template, container]))
        instance = record["instance_id"]
        ports = {int(binding["HostPort"]) for binding in record["bindings"] or []}
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", instance) or len(ports) != 1:
            raise SystemExit("A realtime instance has no unambiguous published port or instance ID")
        if instance in urls:
            raise SystemExit("Realtime containers must have distinct instance IDs")
        port = ports.pop()
        if not 1 <= port <= 65535:
            raise SystemExit("Invalid published port")
        urls[instance] = f"{args.scheme}://{args.public_host}:{port}"
    if not urls:
        raise SystemExit("No running realtime instances found")
    print(json.dumps(urls, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
