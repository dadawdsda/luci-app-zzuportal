#!/bin/sh

. "${ZZUPORTAL_COMMON_SH:-/etc/zzuportal/common.sh}"

zzuportal_load_config
portal_device=$(zzuportal_resolve_device)

if [ -z "$zzuportal_username" ] || [ -z "$zzuportal_password" ]; then
	zzuportal_log err "Login skipped: username or password is not configured."
	echo "Username or password is not configured."
	exit "$ZZUPORTAL_EXIT_AUTH_FAILURE"
fi
if [ -z "$portal_device" ] || [ ! -e "/sys/class/net/$portal_device" ]; then
	zzuportal_log err "Login failed: portal interface is unavailable."
	echo "Portal interface is unavailable."
	exit 1
fi

case "$zzuportal_login_type" in
	0|1) ;;
	*) zzuportal_login_type=0 ;;
esac
encoded_password=$(printf '%s' "$zzuportal_password" | base64 | tr -d '\r\n')

login_attempt_state=""
login_attempt_message=""
perform_login_attempt() {
	local isp="$1"
	local account_value response_body curl_exit_code
	local response_json response_result response_message

	account_value=",${zzuportal_login_type},${zzuportal_username}"
	if [ -n "$isp" ] && [ "$isp" != "zzuwlan" ]; then
		account_value="${account_value}@${isp}"
	fi

	response_body=$(curl -sS --connect-timeout 3 --max-time 30 --interface "$portal_device" --get \
		--data-urlencode "user_account=$account_value" \
		--data-urlencode "user_password=$encoded_password" \
		"$zzuportal_login_url")
	curl_exit_code=$?
	if [ "$curl_exit_code" -ne 0 ]; then
		login_attempt_state="request_failed"
		login_attempt_message="Login request failed (curl $curl_exit_code)."
		return
	fi

	if ! response_json=$(zzuportal_extract_response_json "$response_body" dr1004); then
		login_attempt_state="invalid_response"
		login_attempt_message="Portal returned an empty or unrecognized login response."
		return
	fi

	response_result=$(printf '%s' "$response_json" | jq -r '.result // empty')
	response_message=$(printf '%s' "$response_json" | jq -r '.msg // empty')
	[ -n "$response_message" ] || response_message="Portal login request completed without a message."
	login_attempt_message="$response_message"

	if [ "$response_result" = "1" ]; then
		login_attempt_state="success"
	elif zzuportal_is_auth_failure_message "$response_message"; then
		login_attempt_state="auth_failure"
	elif zzuportal_is_isp_failure_message "$response_message"; then
		login_attempt_state="isp_failure"
	else
		login_attempt_state="rejected"
	fi
}

configured_isp="${zzuportal_isp:-zzuwlan}"
perform_login_attempt "$configured_isp"

case "$login_attempt_state" in
	success)
		zzuportal_log notice "Login succeeded on $portal_device using $configured_isp: $login_attempt_message"
		printf '%s\n' "$login_attempt_message"
		exit 0
		;;
	auth_failure)
		zzuportal_log err "Login credentials were rejected on $portal_device: $login_attempt_message"
		printf '%s\n' "$login_attempt_message"
		exit "$ZZUPORTAL_EXIT_AUTH_FAILURE"
		;;
esac

if [ "$configured_isp" != "zzuwlan" ] &&
	[ "$login_attempt_state" = "isp_failure" ]; then
	primary_failure_message="$login_attempt_message"
	zzuportal_log warning "ISP login via $configured_isp failed: $primary_failure_message; trying ZZUWLAN fallback."
	perform_login_attempt zzuwlan
	case "$login_attempt_state" in
		success)
			zzuportal_log notice "ZZUWLAN fallback login succeeded on $portal_device: $login_attempt_message"
			printf 'ISP %s unavailable; ZZUWLAN fallback succeeded: %s\n' \
				"$configured_isp" "$login_attempt_message"
			exit 0
			;;
		auth_failure)
			zzuportal_log err "ZZUWLAN fallback rejected the configured credentials: $login_attempt_message"
			printf '%s\n' "$login_attempt_message"
			exit "$ZZUPORTAL_EXIT_AUTH_FAILURE"
			;;
		*)
			zzuportal_log err "ZZUWLAN fallback login failed: $login_attempt_message"
			printf 'ISP %s failed: %s; ZZUWLAN fallback failed: %s\n' \
				"$configured_isp" "$primary_failure_message" "$login_attempt_message"
			exit 1
			;;
	esac
fi

zzuportal_log err "Login failed on $portal_device using $configured_isp: $login_attempt_message"
printf '%s\n' "$login_attempt_message"
exit 1
