#!/bin/sh

. "${ZZUPORTAL_COMMON_SH:-/etc/zzuportal/common.sh}"

info_url_override=""
device_override=""

while getopts ":i:d:" option; do
	case "$option" in
		i) info_url_override="$OPTARG" ;;
		d) device_override="$OPTARG" ;;
		*) echo "Usage: status.sh [-i portal_info_url] [-d device]" >&2; exit 2 ;;
	esac
done

zzuportal_load_config
[ -n "$info_url_override" ] && zzuportal_info_url="$info_url_override"
if [ -n "$device_override" ]; then
	portal_device="$device_override"
else
	portal_device=$(zzuportal_resolve_device)
fi

if [ -z "$portal_device" ] || [ ! -e "/sys/class/net/$portal_device" ]; then
	zzuportal_print_status_json -2 error "The portal interface is unavailable."
	exit 1
fi

headers_file=$(mktemp -t zzuportal-headers.XXXXXX) || exit 1
body_file=$(mktemp -t zzuportal-body.XXXXXX) || {
	rm -f "$headers_file"
	exit 1
}
trap 'rm -f "$headers_file" "$body_file"' EXIT INT TERM

curl -sS --connect-timeout 3 --max-time 15 --interface "$portal_device" \
	-D "$headers_file" -o "$body_file" "$zzuportal_info_url"
curl_exit_code=$?

if [ "$curl_exit_code" -eq 0 ]; then
	response_body=$(cat "$body_file")
	if response_json=$(zzuportal_extract_response_json "$response_body" dr1002); then
		response_result=$(printf '%s' "$response_json" | jq -r '.result // empty')
		case "$response_result" in
			1) portal_state="logged_in" ;;
			0) portal_state="logged_out" ;;
			*) portal_state="error" ;;
		esac
		printf '%s' "$response_json" | jq -c --arg state "$portal_state" '. + { state: $state }'
		[ "$portal_state" != "error" ]
		exit $?
	fi

	if zzuportal_is_interception_response "$headers_file" "$body_file"; then
		zzuportal_print_status_json -1 abnormal "Portal interception detected; changing MAC is required."
		exit 0
	fi
	status_error="Portal returned an unrecognized response."
else
	status_error="Portal status request failed (curl $curl_exit_code)."
fi

: >"$headers_file"
: >"$body_file"
if curl -4 -sS --connect-timeout 3 --max-time 5 --interface "$portal_device" \
	-D "$headers_file" -o "$body_file" "$ZZUPORTAL_DEFAULT_INTERCEPTION_PROBE_URL" &&
	zzuportal_is_interception_response "$headers_file" "$body_file"; then
	zzuportal_print_status_json -1 abnormal "Portal interception detected; changing MAC is required."
	exit 0
fi

zzuportal_print_status_json -2 error "$status_error"
exit 1
