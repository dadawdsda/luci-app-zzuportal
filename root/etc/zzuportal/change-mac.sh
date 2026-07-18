#!/bin/sh

. "${ZZUPORTAL_COMMON_SH:-/etc/zzuportal/common.sh}"

zzuportal_load_config
portal_device="${1:-$(zzuportal_resolve_device)}"
sys_class_net="${ZZUPORTAL_SYS_CLASS_NET:-/sys/class/net}"

if [ -z "$portal_device" ] || [ ! -e "$sys_class_net/$portal_device" ]; then
	zzuportal_log err "MAC change failed: interface '$portal_device' is unavailable."
	echo "Interface '$portal_device' is unavailable."
	exit 1
fi

network_device_section=""
configured_mac_address=""
find_network_device_section() {
	local section_id="$1"
	local section_name

	config_get section_name "$section_id" name
	if [ "$section_name" = "$portal_device" ]; then
		network_device_section="$section_id"
		config_get configured_mac_address "$section_id" macaddr
	fi
}

config_load network
config_foreach find_network_device_section device

if ! current_mac_address=$(zzuportal_normalize_mac_address "$configured_mac_address"); then
	detected_mac_address=$(sed -n '1p' "$sys_class_net/$portal_device/address" 2>/dev/null)
	if ! current_mac_address=$(zzuportal_normalize_mac_address "$detected_mac_address"); then
		zzuportal_log err "MAC change failed: no valid MAC found for $portal_device."
		echo "No valid MAC found for '$portal_device'."
		exit 1
	fi
fi
new_mac_address=$(zzuportal_increment_mac_address "$current_mac_address") || exit 1

if [ -z "$network_device_section" ]; then
	network_device_section=$(uci add network device) || exit 1
	uci set "network.$network_device_section.name=$portal_device" || exit 1
fi
if ! uci set "network.$network_device_section.macaddr=$new_mac_address" ||
	! uci commit network; then
	zzuportal_log err "MAC change failed while saving network configuration for $portal_device."
	echo "Failed to save the new MAC for '$portal_device'."
	exit 1
fi

stored_mac_address=$(uci -q get "network.$network_device_section.macaddr")
if [ "$stored_mac_address" != "$new_mac_address" ]; then
	zzuportal_log err "MAC change failed: UCI stored an unexpected value '$stored_mac_address'."
	echo "UCI failed to store the uppercase MAC for '$portal_device'."
	exit 1
fi

if ! ubus call network reload >/dev/null 2>&1; then
	zzuportal_log err "MAC change failed while reloading the network configuration."
	echo "Failed to reload the network configuration."
	exit 1
fi

zzuportal_log notice "Changed MAC configuration on $portal_device from $current_mac_address to $new_mac_address."
printf 'Changed MAC configuration on %s from %s to %s.\n' \
	"$portal_device" "$current_mac_address" "$new_mac_address"
