#!/usr/bin/env python3
"""Check every registered /metrics from the running stack without printing secrets."""
import json
import argparse
import re
import subprocess
import sys


def gateway_exec(container, *args):
    return subprocess.run(["docker", "exec", container, *args], capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-name", default="tamagotchi-go")
    args = parser.parse_args()
    containers = subprocess.run(["docker", "ps", "--filter", "label=com.docker.compose.project=" + args.project_name,
                                 "--filter", "label=com.docker.compose.service=api-gateway", "--format", "{{.ID}}"],
                                capture_output=True, text=True).stdout.splitlines()
    if len(containers) != 1:
        print("Expected one running gateway for the requested Compose project", file=sys.stderr)
        return 1
    container = containers[0]
    result = gateway_exec(container, "wget", "-qO-", "http://service-discovery:8761/api/registry/services")
    if result.returncode:
        print("Cannot read Service Discovery from the running gateway", file=sys.stderr)
        return 1
    targets = [(s["name"], i["instance_id"], f'http://{i["host"]}:{i["port"]}/metrics')
               for s in json.loads(result.stdout)["services"] for i in s["instances"]]
    targets.append(("service-discovery", "service-discovery", "http://service-discovery:8761/metrics"))
    failed = 0
    for service, instance, url in sorted(targets):
        response = gateway_exec(container, "wget", "-T", "5", "-S", "-O", "-", url)
        statuses = re.findall(r"HTTP/\S+ (\d{3})", response.stderr)
        status = statuses[-1] if statuses else "unreachable"
        valid = status == "200" and bool(re.search(r"^(# (HELP|TYPE) |[a-zA-Z_:][\w:]*(?:\{|\s))", response.stdout, re.M))
        print(f"{service:28} {instance:20} HTTP {status:11} {'OK' if valid else 'MISSING/INVALID'}")
        failed += not valid
    print(f"{len(targets) - failed}/{len(targets)} targets expose Prometheus metrics")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
