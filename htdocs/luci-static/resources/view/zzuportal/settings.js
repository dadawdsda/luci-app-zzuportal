'use strict';
'require form';
'require tools.widgets as widgets';
'require view';

var DEFAULT_LOGIN_URL = 'http://172.16.2.9:801/eportal/portal/login?callback=dr1004&login_method=1';
var DEFAULT_LOGOUT_URL = 'http://172.16.2.9:801/eportal/portal/mac/unbind?callback=dr1002';
var DEFAULT_INFO_URL = 'http://172.16.2.9:801/eportal/portal/custom?callback=dr1002';
var DEFAULT_LOG_FILE = '/tmp/log/zzuportal/run.log';

return view.extend({
	render: function() {
		var map = new form.Map('zzuportal', _('Settings'));
		var section;
		var option;
		var loginUrlOption;
		var logoutUrlOption;
		var infoUrlOption;

		section = map.section(form.TypedSection, 'main', _('Main Settings'));
		section.anonymous = true;

		option = section.option(form.Flag, 'enabled', _('Enabled'),
			_('Enable automatic Portal status monitoring and recovery.'));
		option.default = '0';
		option.rmempty = false;

		option = section.option(widgets.DeviceSelect, 'interface', _('Interface'),
			_('Use this device only when it carries an IPv4 default route. The current default-route device is used when unset.'));
		option.rmempty = true;

		option = section.option(form.Value, 'username', _('Username'),
			_('Student ID used for Portal login.'));
		option.rmempty = false;

		option = section.option(form.Value, 'password', _('Password'),
			_('Stored as plain text in UCI and Base64-encoded only when making the login request.'));
		option.password = true;
		option.rmempty = false;

		option = section.option(form.ListValue, 'type', _('Login Type'));
		option.value('0', _('PC'));
		option.value('1', _('Mobile'));
		option.default = '0';
		option.rmempty = false;

		option = section.option(form.ListValue, 'isp', _('ISP'));
		option.value('zzuwlan', _('ZZUWLAN'));
		option.value('cmcc', _('CMCC'));
		option.value('unicom', _('UNICOM'));
		option.value('telecom', _('TELECOM'));
		option.value('zzuplan', _('ZZUPLAN'));
		option.default = 'zzuwlan';
		option.rmempty = false;

		section = map.section(form.TypedSection, 'main', _('Monitoring'));
		section.anonymous = true;

		option = section.option(form.ListValue, 'check_method', _('Connectivity Method'));
		option.value('icmp', _('ICMP'));
		option.value('curl', _('curl'));
		option.default = 'icmp';
		option.rmempty = false;

		option = section.option(form.DynamicList, 'check_address', _('Connectivity Addresses'),
			_('Targets are checked in order until one succeeds. ICMP accepts host names or IP addresses. curl accepts URLs and uses HTTPS when the scheme is omitted.'));
		option.default = [ 'www.baidu.com', 'www.qq.com' ];
		option.rmempty = false;

		option = section.option(form.Value, 'check_interval', _('Check Interval'),
			_('Seconds between status checks.'));
		option.datatype = 'range(5,3600)';
		option.default = '10';
		option.rmempty = false;

		option = section.option(form.Value, 'failure_threshold', _('Failure Threshold'),
			_('Consecutive failed rounds required before checking the Portal status.'));
		option.datatype = 'range(1,20)';
		option.default = '3';
		option.rmempty = false;

		option = section.option(form.Value, 'mac_settle_delay', _('MAC Settle Delay'),
			_('Seconds to wait for the network link after changing the MAC.'));
		option.datatype = 'range(0,60)';
		option.default = '20';
		option.rmempty = false;

		option = section.option(form.Value, 'portal_sync_delay', _('Portal Sync Delay'),
			_('Seconds to wait after logging out the new MAC before logging in.'));
		option.datatype = 'range(5,10)';
		option.default = '5';
		option.rmempty = false;

		section = map.section(form.TypedSection, 'main', _('Logging'));
		section.anonymous = true;

		option = section.option(form.Flag, 'log_to_file', _('Write Logs to File'),
			_('Synchronously append zzuportal logs to the configured file while retaining system logs.'));
		option.default = '1';
		option.rmempty = false;

		option = section.option(form.Value, 'log_file', _('Log File Path'),
			_('Path used for the zzuportal runtime log file.'));
		option.default = DEFAULT_LOG_FILE;
		option.rmempty = false;

		section = map.section(form.TypedSection, 'main', _('Portal URL'),
			_('The Portal URL addresses may vary by region; you can enter a custom URL here.'));
		section.anonymous = true;

		loginUrlOption = section.option(form.Value, 'login_url', _('Login URL'));
		loginUrlOption.default = DEFAULT_LOGIN_URL;
		loginUrlOption.rmempty = false;

		logoutUrlOption = section.option(form.Value, 'logout_url', _('Logout URL'));
		logoutUrlOption.default = DEFAULT_LOGOUT_URL;
		logoutUrlOption.rmempty = false;

		infoUrlOption = section.option(form.Value, 'info_url', _('Info URL'));
		infoUrlOption.default = DEFAULT_INFO_URL;
		infoUrlOption.rmempty = false;

		option = section.option(form.Button, '_restore_default_urls', _('Restore Default URLs'));
		option.inputtitle = _('Restore Defaults');
		option.inputstyle = 'reset';
		option.onclick = function(event, sectionId) {
			loginUrlOption.getUIElement(sectionId).setValue(DEFAULT_LOGIN_URL);
			logoutUrlOption.getUIElement(sectionId).setValue(DEFAULT_LOGOUT_URL);
			infoUrlOption.getUIElement(sectionId).setValue(DEFAULT_INFO_URL);
		};

		return map.render();
	}
});
