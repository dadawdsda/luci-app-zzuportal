#!/bin/sh

. "${ZZUPORTAL_COMMON_SH:-/etc/zzuportal/common.sh}"

script_directory="${ZZUPORTAL_SCRIPT_DIR:-/etc/zzuportal}"
job_state_file="${ZZUPORTAL_RELOGIN_STATE_FILE:-/tmp/zzuportal-relogin.json}"
job_lock_directory="${ZZUPORTAL_RELOGIN_LOCK_DIR:-/tmp/zzuportal-relogin.lock}"
job_start_delay="${ZZUPORTAL_RELOGIN_START_DELAY:-2}"
case "$job_start_delay" in
	''|*[!0-9]*) job_start_delay=2 ;;
esac

write_job_status() {
	local state="$1"
	local message="$2"
	local temporary_file="${job_state_file}.$$"

	jq -cn --arg state "$state" --arg msg "$message" \
		'{ state: $state, msg: $msg }' >"$temporary_file" || return 1
	mv -f "$temporary_file" "$job_state_file"
}

run_relogin() {
	local portal_device

	zzuportal_load_config
	portal_device=$(zzuportal_resolve_device)
	zzuportal_log notice "Starting MAC change and re-login on $portal_device."
	if ! "$script_directory/logout.sh" >/dev/null 2>&1; then
		zzuportal_log warning "Pre-change logout request failed on $portal_device; continuing with the MAC change."
	fi
	"$script_directory/change-mac.sh" "$portal_device" || return $?
	sleep "$zzuportal_mac_settle_delay"
	if ! "$script_directory/logout.sh" >/dev/null 2>&1; then
		zzuportal_log warning "Post-change logout request failed on $portal_device; continuing with re-login."
	fi
	sleep "$zzuportal_portal_sync_delay"
	"$script_directory/login.sh"
}

start_relogin_job() {
	local start_message="MAC change and re-login started in the background."

	if ! mkdir "$job_lock_directory" 2>/dev/null; then
		printf 'MAC change and re-login is already in progress.\n'
		return 0
	fi
	if ! write_job_status running "$start_message"; then
		rmdir "$job_lock_directory" 2>/dev/null
		echo "Failed to create the re-login job status."
		return 1
	fi

	(
		trap 'rmdir "$job_lock_directory" 2>/dev/null' EXIT INT TERM
		sleep "$job_start_delay"
		job_output=$(run_relogin 2>&1)
		job_exit_code=$?
		if [ "$job_exit_code" -eq 0 ]; then
			[ -n "$job_output" ] || job_output="MAC change and re-login completed."
			write_job_status completed "$job_output"
			zzuportal_log notice "Background MAC change and re-login completed."
		else
			[ -n "$job_output" ] || job_output="MAC change and re-login failed."
			write_job_status failed "$job_output"
			zzuportal_log err "Background MAC change and re-login failed: $job_output"
		fi
	) </dev/null >/dev/null 2>&1 &

	printf '%s\n' "$start_message"
}

read_relogin_job_status() {
	if [ -s "$job_state_file" ]; then
		cat "$job_state_file"
	else
		jq -cn '{ state: "idle", msg: "No MAC change and re-login job is running." }'
	fi
}

case "${1:---run}" in
	--run) run_relogin ;;
	--start) start_relogin_job ;;
	--status) read_relogin_job_status ;;
	*) echo "Usage: relogin.sh [--run|--start|--status]" >&2; exit 2 ;;
esac
