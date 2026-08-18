#!/bin/sh

ZZUPORTAL_FUNCTIONS_SH=/dev/null
. "$ZZUPORTAL_PROJECT_ROOT/root/etc/zzuportal/common.sh"

zzuportal_load_config() {
	zzuportal_info_url="http://portal.test:801/info"
}

zzuportal_resolve_device() {
	printf '%s' lo
}
