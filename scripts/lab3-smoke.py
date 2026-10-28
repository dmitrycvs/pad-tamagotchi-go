#!/usr/bin/env python3
"""Isolated Lab 3 smoke test; uses only disposable containers and test credentials."""
import argparse
import base64
import hashlib
import hmac
import json
import subprocess
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
USER_SECRET = "test_user_secret_with_at_least_32_characters!"
SERVICE_SECRET = "test_service_secret_with_at_least_32_chars!!"
GATEWAY_SECRET = "test_gateway_secret_for_lab3_smoke_only"


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True, stderr=subprocess.STDOUT).strip()


def wait(check, description, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                return value
        except Exception:
            pass
        time.sleep(0.5)
    raise RuntimeError("Timed out: " + description)


def request(url, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, json.load(response)


def user_token(subject):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=")
    message = encode({"alg": "HS256", "typ": "JWT"}) + b"." + encode(
        {"sub": subject, "roles": ["user", "admin"], "iat": int(time.time()), "exp": int(time.time()) + 3600})
    signature = base64.urlsafe_b64encode(hmac.new(USER_SECRET.encode(), message, hashlib.sha256).digest()).rstrip(b"=")
    return (message + b"." + signature).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="Build the four local service images first")
    args = parser.parse_args()
    if args.build:
        for directory, image in [("guild-service", "guild-service"), ("package-registry", "package-registry-service"),
                                 ("service-discovery", "service-discovery"), ("api-gateway", "api-gateway")]:
            subprocess.run(["docker", "build", "--platform", "linux/amd64", "-t",
                            "tamagotchi-lab3/" + image + ":local", str(ROOT / directory)], check=True)
    prefix = "pad-lab3-smoke-" + uuid.uuid4().hex[:8]
    containers = []
    docker("network", "create", prefix)

    def start(name, image, port, env, platform=True):
        name = prefix + "-" + name
        command = ["run", "--detach", "--name", name, "--hostname", name, "--network", prefix,
                   "-p", f"127.0.0.1::{port}"]
        if platform:
            command += ["--platform", "linux/amd64"]
        for key, value in env.items():
            command += ["-e", f"{key}={value}"]
        docker(*command, image)
        containers.append(name)
        return "http://" + docker("port", name, f"{port}/tcp").splitlines()[0]

    def service(name, image, env):
        return start(name, "tamagotchi-lab3/" + image + ":local", 8080, env)

    try:
        start("db", "postgres:16-alpine", 5432,
              {"POSTGRES_USER": "test", "POSTGRES_PASSWORD": "test", "POSTGRES_DB": "guild"}, platform=False)
        wait(lambda: "accepting connections" in docker("exec", prefix + "-db", "pg_isready", "-U", "test"), "PostgreSQL")
        docker("exec", prefix + "-db", "createdb", "-U", "test", "package_registry")
        discovery = start("discovery", "tamagotchi-lab3/service-discovery:local", 8761,
                          {"HEALTH_CHECK_INTERVAL": "1s", "HEALTH_CHECK_TIMEOUT": "2s", "DISCORD_WEBHOOK_URL": ""})
        wait(lambda: request(discovery + "/health")[0] == 200, "discovery health")
        common = {"SERVICE_DISCOVERY_URL": f"http://{prefix}-discovery:8761", "PORT": "8080",
                  "API_GATEWAY_URL": f"http://{prefix}-gateway:8080", "GATEWAY_SHARED_SECRET": GATEWAY_SECRET,
                  "SERVICE_JWT_SECRET": SERVICE_SECRET}
        guilds = [service("guild-" + str(index), "guild-service", dict(common,
                  DATABASE_URL=f"postgres://test:test@{prefix}-db:5432/guild?sslmode=disable")) for index in [1, 2]]
        registry = service("registry", "package-registry-service", dict(common,
                           DATABASE_URL=f"postgres://test:test@{prefix}-db:5432/package_registry?sslmode=disable"))
        gateway = service("gateway", "api-gateway", dict(common, JWT_SECRET=USER_SECRET, DISCORD_WEBHOOK_URL=""))
        for address in [*guilds, registry, gateway]:
            wait(lambda address=address: request(address + "/health")[0] == 200, "service health")

        def snapshot():
            return {s["name"]: s["instances"] for s in request(discovery + "/api/registry/services")[1]["services"]}

        def registered():
            state = snapshot()
            return len(state.get("guild-service", [])) == 2 and len(state.get("package-registry-service", [])) == 1 \
                and len(state.get("api-gateway", [])) == 1
        wait(registered, "two Guild replicas, Registry and Gateway registrations")

        def healthy():
            instances = [i for name in ["guild-service", "package-registry-service"] for i in snapshot().get(name, [])]
            return len(instances) == 3 and all((i.get("health") or {}).get("condition") == "ok" for i in instances)
        wait(healthy, "real registry health polling of Go load fields")
        print("PASS: distinct replica ids, registration and real health polling", flush=True)
        subject = str(uuid.uuid4())
        token = user_token(subject)
        body = {"name": "smoke-" + uuid.uuid4().hex[:8], "owner_id": subject, "event_id": str(uuid.uuid4())}
        _, created = wait(lambda: request(gateway + "/api/guilds", body, token), "trusted gateway creation")
        guild_id = created["guild_id"]
        for _ in range(4):
            assert request(gateway + "/api/guilds/" + guild_id, token=token)[0] == 200
        for index in [1, 2]:
            assert "path=/api/guilds/" + guild_id in docker("logs", prefix + "-guild-" + str(index))
        assert request(gateway + "/api/packages", {"name": "smoke-" + uuid.uuid4().hex[:8], "version": "1.0.0",
                       "moderator_ids": [subject], "event_id": str(uuid.uuid4())}, token)[0] == 201
        print("PASS: trusted gateway writes, reads and round-robin across both Guild replicas", flush=True)
        docker("stop", "--time", "15", prefix + "-guild-2")
        wait(lambda: len(snapshot().get("guild-service", [])) == 1, "SIGTERM deregistration", seconds=5)
        print("PASS: graceful deregistration", flush=True)
    except Exception:
        for name in containers:
            print(name, docker("logs", "--tail", "15", name), flush=True)
        raise
    finally:
        for name in reversed(containers):
            docker("rm", "--force", "--volumes", name)
        docker("network", "rm", prefix)


if __name__ == "__main__":
    main()
