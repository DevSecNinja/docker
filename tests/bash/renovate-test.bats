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
match = re.search(
    r'description:\s*"Enable digest updates for DevSecNinja devcontainer images"(?P<body>.*?)\n\s*},',
    config,
    re.S,
)
if not match:
    raise SystemExit("Renovate devcontainer digest package rule is missing")

body = match.group("body")
required_patterns = [
    r'matchManagers:\s*\["devcontainer"\]',
    r'matchDatasources:\s*\["docker"\]',
    r'matchPackageNames:\s*\[[^\]]*ghcr[^\]]*devsecninja[^\]]*\]',
    r'matchUpdateTypes:\s*\["digest"\]',
    r'enabled:\s*true',
    r'minimumReleaseAge:\s*"0"',
]
missing = [pattern for pattern in required_patterns if not re.search(pattern, body)]
if missing:
    raise SystemExit(f"Renovate devcontainer digest package rule missing: {missing}")
PY
	[ "$status" -eq 0 ]
}
