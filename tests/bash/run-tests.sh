#!/bin/bash
# Bash Test Runner
# Runs all Bats tests for Ansible and Docker infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CI_MODE=false
OUTPUT_FILE="test-results.tap"
OUTPUT_FORMAT="tap"
SPECIFIC_TESTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--ci)
		CI_MODE=true
		OUTPUT_FORMAT="junit"
		OUTPUT_FILE="test-results.xml"
		shift
		;;
	--output)
		OUTPUT_FILE="$2"
		shift 2
		;;
	--test)
		SPECIFIC_TESTS+=("$2")
		shift 2
		;;
	-h | --help)
		echo "Usage: $0 [OPTIONS]"
		echo "Run Bats tests for Ansible and Docker infrastructure"
		echo ""
		echo "Options:"
		echo "  --ci              Run in CI mode (installs dependencies, exits on failure)"
		echo "                    Automatically uses JUnit XML format for test results"
		echo "  --output FILE     Output file for test results"
		echo "                    (default: test-results.tap, or test-results.xml in CI mode)"
		echo "  --test FILE       Run specific test file (can be used multiple times)"
		echo "  -h, --help        Show this help message"
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Bash Test Suite with Bats           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verify tool versions match .mise.toml
if command -v mise >/dev/null 2>&1; then
	echo -e "${BLUE}🔍 Checking tool versions via mise...${NC}"
	MISE_OUTDATED=$(mise ls --missing 2>/dev/null || true)
	if [ -n "$MISE_OUTDATED" ]; then
		echo -e "${YELLOW}⚠️  Some mise tools are missing or outdated:${NC}"
		echo "$MISE_OUTDATED"
		echo -e "${YELLOW}   Running 'mise install' to sync...${NC}"
		mise install 2>&1
	fi
	echo -e "${GREEN}✅ Tool versions match .mise.toml${NC}"
	mise ls 2>/dev/null
	echo ""
else
	echo -e "${YELLOW}⚠️  mise not found — tool versions not verified against .mise.toml${NC}"
	echo -e "${YELLOW}   Install mise: https://mise.jdx.dev/${NC}"
	echo ""
fi

# Check if bats is installed
if ! command -v bats >/dev/null 2>&1; then
	echo -e "${YELLOW}📦 Bats not found, installing...${NC}"

	if [ "$CI_MODE" = true ]; then
		# Install in CI mode
		echo "Installing Bats from GitHub..."
		BATS_VERSION="1.13.0"
		git clone --depth 1 --branch "v${BATS_VERSION}" https://github.com/bats-core/bats-core.git /tmp/bats-core
		cd /tmp/bats-core
		sudo ./install.sh /usr/local
		cd -
		rm -rf /tmp/bats-core
	else
		# Try to install locally
		if command -v npm >/dev/null 2>&1; then
			echo "Installing Bats via npm..."
			npm install -g bats
		elif command -v brew >/dev/null 2>&1; then
			echo "Installing Bats via Homebrew..."
			brew install bats-core
		else
			echo -e "${RED}❌ Cannot install Bats automatically${NC}"
			echo "Please install Bats manually:"
			echo "  - macOS: brew install bats-core"
			echo "  - Ubuntu/Debian: sudo apt-get install bats"
			echo "  - npm: npm install -g bats"
			echo "  - Manual: https://github.com/bats-core/bats-core#installation"
			exit 1
		fi
	fi

	# Verify installation
	if ! command -v bats >/dev/null 2>&1; then
		echo -e "${RED}❌ Bats installation failed${NC}"
		exit 1
	fi
fi

# Display Bats version
BATS_VERSION=$(bats --version)
echo -e "${GREEN}✅ Bats is available: ${BATS_VERSION}${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}"

# Make OUTPUT_FILE path absolute if it's relative
if [[ ! "$OUTPUT_FILE" = /* ]]; then
	OUTPUT_FILE="${SCRIPT_DIR}/${OUTPUT_FILE}"
fi

# Find all .bats test files
echo -e "${BLUE}🔍 Discovering test files...${NC}"
TEST_FILES=()

if [ ${#SPECIFIC_TESTS[@]} -gt 0 ]; then
	# Run specific tests
	for test in "${SPECIFIC_TESTS[@]}"; do
		if [ -f "${TESTS_DIR}/${test}" ]; then
			TEST_FILES+=("${TESTS_DIR}/${test}")
			echo "  📝 Found: $(basename "$test")"
		elif [ -f "$test" ]; then
			TEST_FILES+=("$test")
			echo "  📝 Found: $(basename "$test")"
		else
			echo "  ❌ Test not found: $test"
			exit 1
		fi
	done
else
	# Run all tests
	while IFS= read -r -d '' file; do
		TEST_FILES+=("$file")
		echo "  📝 Found: $(basename "$file")"
	done < <(find "$TESTS_DIR" -name "*.bats" -print0)
fi

if [ ${#TEST_FILES[@]} -eq 0 ]; then
	echo -e "${YELLOW}⚠️  No test files found in $TESTS_DIR${NC}"
	exit 0
fi

echo ""
echo -e "${BLUE}🧪 Running ${#TEST_FILES[@]} test file(s)...${NC}"
echo ""

# Run tests
if [ "$CI_MODE" = true ]; then
	# In CI mode, produce human-readable output on terminal AND JUnit XML for reporting
	if [ "$OUTPUT_FORMAT" = "junit" ]; then
		# Run with pretty terminal output and a separate JUnit report file
		# --report-formatter writes JUnit XML to --output directory
		REPORT_DIR="$(dirname "$OUTPUT_FILE")"
		bats --formatter tap --report-formatter junit --output "$REPORT_DIR" "${TEST_FILES[@]}"
		EXIT_CODE=$?
		# Rename the report file to the expected output filename
		if [ -f "${REPORT_DIR}/report.xml" ]; then
			mv "${REPORT_DIR}/report.xml" "$OUTPUT_FILE"
		fi
	else
		# Use TAP format
		bats --tap "${TEST_FILES[@]}" 2>&1 | tee "$OUTPUT_FILE"
		EXIT_CODE=${PIPESTATUS[0]}
	fi
else
	# In interactive mode, show output directly (no file needed)
	bats "${TEST_FILES[@]}"
	EXIT_CODE=$?
fi

# Display results based on exit code
echo ""
if [ $EXIT_CODE -eq 0 ]; then
	echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║   ✅ All Tests Passed!                ║${NC}"
	echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
else
	echo -e "${RED}╔════════════════════════════════════════╗${NC}"
	echo -e "${RED}║   ❌ Some Tests Failed                ║${NC}"
	echo -e "${RED}╚════════════════════════════════════════╝${NC}"
fi

# In CI mode, display full output and summary
if [ "$CI_MODE" = true ]; then
	echo ""
	echo -e "${BLUE}📊 Test Results Summary:${NC}"
	if [ -f "$OUTPUT_FILE" ]; then
		if [ "$OUTPUT_FORMAT" = "junit" ]; then
			echo "  JUnit XML report generated: $OUTPUT_FILE"
			# Display a simple summary from JUnit XML
			if command -v xmllint >/dev/null 2>&1; then
				# Validate XML first
				if xmllint --noout "$OUTPUT_FILE" 2>/dev/null; then
					TOTAL=$(xmllint --xpath "count(//testcase)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					FAILURES=$(xmllint --xpath "count(//testcase/failure)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					ERRORS=$(xmllint --xpath "count(//testcase/error)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					echo "  Total: $TOTAL, Failures: $FAILURES, Errors: $ERRORS"
				else
					echo "  ⚠️  Warning: XML report is malformed or empty. Check test execution for errors."
				fi
			else
				echo "  ℹ️  xmllint not available for detailed summary"
			fi
		else
			# TAP format summary
			grep -E "^(ok|not ok)" "$OUTPUT_FILE" | sort | uniq -c || echo "  No test results found"
		fi
	fi

	if [ "$OUTPUT_FORMAT" = "tap" ]; then
		echo ""
		echo -e "${BLUE}📋 Full Test Output:${NC}"
		cat "$OUTPUT_FILE"
	fi
fi

exit $EXIT_CODE
