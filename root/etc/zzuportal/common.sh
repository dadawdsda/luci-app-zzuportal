#!/bin/sh

. "${ZZUPORTAL_FUNCTIONS_SH:-/lib/functions.sh}"

ZZUPORTAL_LOG_TAG="zzuportal"
ZZUPORTAL_DEFAULT_LOGIN_URL="http://172.16.2.9:801/eportal/portal/login?callback=dr1004&login_method=1"
ZZUPORTAL_DEFAULT_LOGOUT_URL="http://172.16.2.9:801/eportal/portal/mac/unbind?callback=dr1002"
ZZUPORTAL_DEFAULT_INFO_URL="http://172.16.2.9:801/eportal/portal/custom?callback=dr1002"
ZZUPORTAL_DEFAULT_INTERCEPTION_PROBE_URL="http://172.16.2.9/"
ZZUPORTAL_DEFAULT_CHECK_ADDRESSES="www.baidu.com
www.qq.com"
ZZUPORTAL_DEFAULT_CHECK_METHOD="icmp"
ZZUPORTAL_DEFAULT_CHECK_INTERVAL=10
ZZUPORTAL_DEFAULT_FAILURE_THRESHOLD=3
ZZUPORTAL_DEFAULT_MAC_SETTLE_DELAY=20
ZZUPORTAL_DEFAULT_PORTAL_SYNC_DELAY=5
ZZUPORTAL_EXIT_AUTH_FAILURE=10

zzuportal_log() {
	local priority="$1"
	shift

	[ "$priority" = "warning" ] && priority="warn"
	logger -t "$ZZUPORTAL_LOG_TAG" -p "daemon.$priority" "$*"
}

zzuportal_get_default_route_device() {
	ip -4 route show default 2>/dev/null | awk '
		$1 == "default" {
			for (i = 1; i <= NF; i++)
				if ($i == "dev") { print $(i + 1); exit }
		}'
}

zzuportal_device_has_default_route() {
	local device="$1"

	[ -n "$device" ] || return 1
	ip -4 route show default 2>/dev/null | awk -v device="$device" '
		$1 == "default" {
			for (i = 1; i <= NF; i++)
				if ($i == "dev" && $(i + 1) == device) found = 1
		}
		END { exit !found }'
}

zzuportal_add_check_address() {
	local address="$1"

	[ -n "$address" ] || return
	if [ -n "$zzuportal_check_addresses" ]; then
		zzuportal_check_addresses="$zzuportal_check_addresses
$address"
	else
		zzuportal_check_addresses="$address"
	fi
}

zzuportal_load_config() {
	local legacy_check_host

	config_load zzuportal
	config_get zzuportal_enabled main enabled "0"
	config_get zzuportal_interface main interface
	config_get zzuportal_username main username
	config_get zzuportal_password main password
	config_get zzuportal_login_type main type "0"
	config_get zzuportal_isp main isp "zzuwlan"
	config_get zzuportal_login_url main login_url "$ZZUPORTAL_DEFAULT_LOGIN_URL"
	config_get zzuportal_logout_url main logout_url "$ZZUPORTAL_DEFAULT_LOGOUT_URL"
	config_get zzuportal_info_url main info_url "$ZZUPORTAL_DEFAULT_INFO_URL"
	zzuportal_check_addresses=""
	config_list_foreach main check_address zzuportal_add_check_address
	config_get legacy_check_host main check_host
	config_get zzuportal_check_method main check_method "$ZZUPORTAL_DEFAULT_CHECK_METHOD"
	config_get zzuportal_check_interval main check_interval "$ZZUPORTAL_DEFAULT_CHECK_INTERVAL"
	config_get zzuportal_failure_threshold main failure_threshold "$ZZUPORTAL_DEFAULT_FAILURE_THRESHOLD"
	config_get zzuportal_mac_settle_delay main mac_settle_delay "$ZZUPORTAL_DEFAULT_MAC_SETTLE_DELAY"
	config_get zzuportal_portal_sync_delay main portal_sync_delay "$ZZUPORTAL_DEFAULT_PORTAL_SYNC_DELAY"

	[ -n "$zzuportal_login_url" ] || zzuportal_login_url="$ZZUPORTAL_DEFAULT_LOGIN_URL"
	[ -n "$zzuportal_logout_url" ] || zzuportal_logout_url="$ZZUPORTAL_DEFAULT_LOGOUT_URL"
	[ -n "$zzuportal_info_url" ] || zzuportal_info_url="$ZZUPORTAL_DEFAULT_INFO_URL"
	if [ -z "$zzuportal_check_addresses" ]; then
		zzuportal_check_addresses="${legacy_check_host:-$ZZUPORTAL_DEFAULT_CHECK_ADDRESSES}"
	fi
	case "$zzuportal_check_method" in
		icmp|curl) ;;
		*) zzuportal_check_method="$ZZUPORTAL_DEFAULT_CHECK_METHOD" ;;
	esac
	case "$zzuportal_check_interval" in
		''|*[!0-9]*) zzuportal_check_interval="$ZZUPORTAL_DEFAULT_CHECK_INTERVAL" ;;
	esac
	[ "$zzuportal_check_interval" -ge 5 ] 2>/dev/null || zzuportal_check_interval=5
	case "$zzuportal_failure_threshold" in
		''|*[!0-9]*) zzuportal_failure_threshold="$ZZUPORTAL_DEFAULT_FAILURE_THRESHOLD" ;;
	esac
	if [ "$zzuportal_failure_threshold" -lt 1 ] 2>/dev/null ||
		[ "$zzuportal_failure_threshold" -gt 20 ] 2>/dev/null; then
		zzuportal_failure_threshold="$ZZUPORTAL_DEFAULT_FAILURE_THRESHOLD"
	fi
	case "$zzuportal_mac_settle_delay" in
		''|*[!0-9]*) zzuportal_mac_settle_delay="$ZZUPORTAL_DEFAULT_MAC_SETTLE_DELAY" ;;
	esac
	case "$zzuportal_portal_sync_delay" in
		''|*[!0-9]*) zzuportal_portal_sync_delay="$ZZUPORTAL_DEFAULT_PORTAL_SYNC_DELAY" ;;
	esac
	if [ "$zzuportal_portal_sync_delay" -lt 5 ] 2>/dev/null ||
		[ "$zzuportal_portal_sync_delay" -gt 10 ] 2>/dev/null; then
		zzuportal_portal_sync_delay="$ZZUPORTAL_DEFAULT_PORTAL_SYNC_DELAY"
	fi
}

zzuportal_resolve_device() {
	if [ -n "$zzuportal_interface" ]; then
		printf '%s' "$zzuportal_interface"
	else
		zzuportal_get_default_route_device
	fi
}

zzuportal_check_connectivity() {
	local device="$1"
	local address original_ifs probe_target

	[ -n "$device" ] || return 1
	original_ifs="$IFS"
	IFS='
'
	for address in $zzuportal_check_addresses; do
		[ -n "$address" ] || continue
		case "$zzuportal_check_method" in
			curl)
				case "$address" in
					*://*) probe_target="$address" ;;
					*) probe_target="https://$address" ;;
				esac
				if curl -4 -sS --connect-timeout 3 --max-time 5 --interface "$device" \
					-o /dev/null "$probe_target" >/dev/null 2>&1; then
					IFS="$original_ifs"
					return 0
				fi
				;;
			*)
				probe_target="${address#*://}"
				probe_target="${probe_target%%/*}"
				probe_target="${probe_target%%\?*}"
				probe_target="${probe_target%%:*}"
				if ping -I "$device" -c 1 -W 3 "$probe_target" >/dev/null 2>&1; then
					IFS="$original_ifs"
					return 0
				fi
				;;
		esac
	done
	IFS="$original_ifs"
	return 1
}

zzuportal_normalize_mac_address() {
	local mac_address="$1"

	printf '%s' "$mac_address" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' || return 1
	printf '%s' "$mac_address" | tr '[a-z]' '[A-Z]'
}

zzuportal_increment_mac_address() {
	local mac_address
	local original_ifs mac_prefix suffix_value next_suffix

	mac_address=$(zzuportal_normalize_mac_address "$1") || return 1
	original_ifs="$IFS"
	IFS=':'
	set -- $mac_address
	IFS="$original_ifs"

	mac_prefix="$1:$2:$3:$4"
	suffix_value=$((0x${5}${6}))
	next_suffix=$(printf '%04X' "$(((suffix_value + 1) % 65536))")
	printf '%s:%s:%s' \
		"$mac_prefix" \
		"$(printf '%s' "$next_suffix" | cut -c1-2)" \
		"$(printf '%s' "$next_suffix" | cut -c3-4)"
}

zzuportal_extract_response_json() {
	local response_body="$1"
	local callback_name
	local json_payload

	if json_payload=$(printf '%s' "$response_body" | jq -ce 'select(type == "object")' 2>/dev/null) &&
		[ -n "$json_payload" ]; then
		printf '%s' "$json_payload"
		return
	fi

	shift
	for callback_name in "$@"; do
		case "$callback_name" in
			''|*[!A-Za-z0-9_]*) continue ;;
		esac
		json_payload=$(printf '%s' "$response_body" | tr -d '\r' |
			sed -n "s/^${callback_name}(\(.*\));$/\1/p")
		if [ -n "$json_payload" ] && printf '%s' "$json_payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
			printf '%s' "$json_payload" | jq -c .
			return
		fi
	done

	return 1
}

zzuportal_is_auth_failure_message() {
	local message

	message=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	case "$message" in
		"ldap auth error"|"账号不存在") return 0 ;;
		*) return 1 ;;
	esac
}

zzuportal_is_isp_failure_message() {
	printf '%s' "$1" | grep -Eqi \
		'^[[:space:]]*Rad:|PPPOE[[:space:]]*会话|代拨认证超时'
}

zzuportal_print_status_json() {
	local result="$1"
	local state="$2"
	local message="$3"

	jq -cn --argjson result "$result" --arg state "$state" --arg msg "$message" \
		'{ result: $result, state: $state, msg: $msg }'
}

zzuportal_is_interception_response() {
	local headers_file="$1"
	local body_file="$2"

	grep -Eqi '^Server:[[:space:]]*MAGI([[:space:]]|/|$)' "$headers_file" && return 0
	grep -Fq 'location.replace(' "$body_file" &&
		grep -Eq '/portal\.do\?wlanuserip=' "$body_file" && return 0
	return 1
}
