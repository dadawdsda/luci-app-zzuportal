#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_tmp=$(mktemp -d -t zzuportal-tests.XXXXXX)
trap 'rm -rf "$test_tmp"' EXIT INT TERM

export ZZUPORTAL_PROJECT_ROOT="$project_root"
export ZZUPORTAL_COMMON_SH="$project_root/tests/fixtures/common.sh"
export ZZUPORTAL_CURL_LOG="$test_tmp/curl.log"
PATH="$project_root/tests/fixtures/bin:$PATH"
export PATH

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

run_case() {
	name="$1"
	scenario="$2"
	expected_exit="$3"
	expected_state="$4"
	expected_calls="$5"
	expected_message="$6"

	: >"$ZZUPORTAL_CURL_LOG"
	export ZZUPORTAL_TEST_SCENARIO="$scenario"
	set +e
	output=$(sh "$project_root/root/etc/zzuportal/status.sh" -d lo 2>/dev/null)
	actual_exit=$?
	set -e

	[ "$actual_exit" -eq "$expected_exit" ] ||
		fail "$name returned $actual_exit, expected $expected_exit"
	actual_state=$(printf '%s' "$output" | jq -r '.state')
	[ "$actual_state" = "$expected_state" ] ||
		fail "$name returned state $actual_state, expected $expected_state"
	actual_calls=$(wc -l <"$ZZUPORTAL_CURL_LOG" | tr -d ' ')
	[ "$actual_calls" -eq "$expected_calls" ] ||
		fail "$name made $actual_calls curl calls, expected $expected_calls"
	if [ -n "$expected_message" ]; then
		actual_message=$(printf '%s' "$output" | jq -r '.msg')
		[ "$actual_message" = "$expected_message" ] ||
			fail "$name returned message '$actual_message', expected '$expected_message'"
	fi
	echo "PASS: $name"
}

run_case logged-out logged_out 0 logged_out 1 ""
run_case direct-interception direct_interception 0 abnormal 1 ""
run_case timeout-interception timeout_interception 0 abnormal 2 ""
run_case unrecognized-interception unrecognized_interception 0 abnormal 2 ""
run_case timeout-error timeout_error 1 error 2 'Portal status request failed (curl 28).'
run_case timeout-plain-http timeout_plain_http 1 error 2 'Portal status request failed (curl 28).'
