#!/bin/sh

. "${ZZUPORTAL_COMMON_SH:-/etc/zzuportal/common.sh}"

zzuportal_load_config
portal_device=$(zzuportal_resolve_device)

if [ -z "$portal_device" ] || [ ! -e "/sys/class/net/$portal_device" ]; then
	zzuportal_log err "Logout failed: portal interface is unavailable."
	echo "Portal interface is unavailable."
	exit 1
fi

response_body=$(curl -sS --connect-timeout 3 --max-time 30 --interface "$portal_device" "$zzuportal_logout_url")
curl_exit_code=$?
if [ "$curl_exit_code" -ne 0 ]; then
	zzuportal_log err "Logout request failed on $portal_device (curl $curl_exit_code)."
	echo "Logout request failed (curl $curl_exit_code)."
	exit 1
fi

if ! response_json=$(zzuportal_extract_response_json "$response_body" dr1002 dr1004); then
	zzuportal_log err "Logout failed: Portal returned an unrecognized response."
	echo "Portal returned an unrecognized logout response."
	exit 1
fi

response_result=$(printf '%s' "$response_json" | jq -r '.result // empty')
response_message=$(printf '%s' "$response_json" | jq -r '.msg // "Portal logout request completed."')
if [ "$response_result" != "1" ]; then
	zzuportal_log err "Logout rejected on $portal_device: $response_message"
	printf '%s\n' "$response_message"
	exit 1
fi

zzuportal_log notice "Logout completed on $portal_device: $response_message"
printf '%s\n' "$response_message"
