#!/usr/bin/env bats
# Tests for Renovate configuration

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	RENOVATE_CONFIG="${REPO_ROOT}/renovate.json5"
	export RENOVATE_CONFIG
}

@test "renovate-test: enables digest updates for DevSecNinja devcontainer images" {
	run python3 - <<'PY'
from pathlib import Path
import os
import re

config = Path(os.environ["RENOVATE_CONFIG"]).read_text()

description = 'description: "Enable digest updates for DevSecNinja devcontainer images"'
description_index = config.find(description)
if description_index == -1:
    raise SystemExit("Renovate devcontainer digest package rule is missing")

rule_start = config.rfind("{", 0, description_index)
if rule_start == -1:
    raise SystemExit("Renovate devcontainer digest package rule start is missing")

depth = 0
rule_end = None
for index, character in enumerate(config[rule_start:], start=rule_start):
    if character == "{":
        depth += 1
    elif character == "}":
        depth -= 1
        if depth == 0:
            rule_end = index + 1
            break

if rule_end is None:
    raise SystemExit("Renovate devcontainer digest package rule end is missing")

rule = config[rule_start:rule_end]

def array_values(key):
    match = re.search(rf'{key}:\s*\[(?P<values>[^\]]*)\]', rule, re.S)
    if not match:
        return []
    return [
        value.strip().strip('"\'')
        for value in match.group("values").split(",")
        if value.strip()
    ]

checks = {
    "matchManagers": "devcontainer" in array_values("matchManagers"),
    "matchDatasources": "docker" in array_values("matchDatasources"),
    "matchPackageNames": "/^ghcr\\\\.io\\\\/devsecninja\\\\//" in array_values("matchPackageNames"),
    "matchUpdateTypes": "digest" in array_values("matchUpdateTypes"),
    "enabled": re.search(r'enabled:\s*true\b', rule) is not None,
    "minimumReleaseAge": re.search(r'minimumReleaseAge:\s*"0"', rule) is not None,
}
missing = [name for name, found in checks.items() if not found]
if missing:
    raise SystemExit(f"Renovate devcontainer digest package rule missing: {missing}")
PY
	[ "$status" -eq 0 ]
}
