'use strict';
'require rpc';
'require view';

var callGetInfo = rpc.declare({
	object: 'luci.zzuportal',
	method: 'status',
	timeout: 120000
});

var callLogin = rpc.declare({
	object: 'luci.zzuportal',
	method: 'login',
	timeout: 120000
});

var callLogout = rpc.declare({
	object: 'luci.zzuportal',
	method: 'logout',
	timeout: 120000
});

var callRelogin = rpc.declare({
	object: 'luci.zzuportal',
	method: 'relogin',
	timeout: 10000
});

var callGetReloginStatus = rpc.declare({
	object: 'luci.zzuportal',
	method: 'relogin_status',
	timeout: 10000
});

var STATUS_FIELDS = [
	{ key: 'param_account', label: _('Account') },
	{ key: 'param_exit', label: _('NetworkExit') },
	{ key: 'param_duration', label: _('Duration') },
	{ key: 'param_ip', label: _('IP') }
];
var ACTION_REFRESH_DELAY = 2000;
var RELOGIN_POLL_INTERVAL = 2000;

return view.extend({
	render: function() {
		var viewInstance = this;
		var statusTable = E('table', { 'class': 'table', 'id': 'zzu-info-table' });

		for (var index = 0; index < STATUS_FIELDS.length; index++) {
			var field = STATUS_FIELDS[index];
			statusTable.appendChild(
				E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '33%' }, [field.label]),
					E('td', {
						'class': 'td left zzu-portal-loading',
						'id': 'zzu-cell-' + field.key
					}, [E('em', _('Loading...'))])
				]));
		}

		statusTable.appendChild(
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [_('Message')]),
				E('td', {
					'class': 'td left zzu-portal-loading',
					'id': 'zzu-cell-msg'
				}, [E('em', _('Loading...'))])
			]));

		var container = E('div', {}, [
			E('div', { 'class': 'cbi-map', 'id': 'map' }, [
				E('div', { 'class': 'cbi-section', 'id': 'cbi-sample-js' }, [
					E('div', { 'class': 'left', 'id': 'zzuportal-status' }, [
						E('h3', _('User login information')),
						statusTable,
						viewInstance._renderActionButtons()
					])
				])
			]),
			E('div', { 'id': 'zzuportal-status-msg', 'class': 'cbi-section' })
		]);

		window.setTimeout(function() {
			viewInstance._initializeStatus();
		}, 10);

		return container;
	},

	_initializeStatus: function() {
		var viewInstance = this;

		return callGetReloginStatus()
			.then(function(jobStatus) {
				if (jobStatus && jobStatus.state === 'running') {
					viewInstance._showMessage(
						jobStatus.msg || _('%s in progress...').format(_('Change MAC & Re-login')),
						false);
					viewInstance._scheduleReloginStatusPoll();
					return;
				}

				return viewInstance._refreshStatus();
			})
			.catch(function() {
				return viewInstance._refreshStatus();
			});
	},

	_refreshStatus: function() {
		var viewInstance = this;

		viewInstance._showMessage(_('Fetching data...'), false);
		viewInstance._setAllCellsLoading();

		return callGetInfo()
			.then(function(statusInfo) {
				viewInstance._updateCells(statusInfo);
				if (statusInfo && (statusInfo.state === 'error' || statusInfo.state === 'abnormal'))
					viewInstance._showMessage(statusInfo.msg || _('Refresh failed'), true);
				else
					viewInstance._showMessage(_('Refresh complete'), false);
			})
			.catch(function(error) {
				var errorMessage = error.message || String(error);
				viewInstance._setAllCellsError(errorMessage);
				viewInstance._showMessage(_('Refresh failed: ') + errorMessage, true);
			});
	},

	_setAllCellsLoading: function() {
		for (var index = 0; index < STATUS_FIELDS.length; index++) {
			var cell = document.getElementById('zzu-cell-' + STATUS_FIELDS[index].key);
			if (cell) {
				cell.innerHTML = '';
				cell.className = 'td left zzu-portal-loading';
				cell.appendChild(E('em', _('Loading...')));
			}
		}

		var messageCell = document.getElementById('zzu-cell-msg');
		if (messageCell) {
			messageCell.innerHTML = '';
			messageCell.className = 'td left zzu-portal-loading';
			messageCell.appendChild(E('em', _('Loading...')));
		}
	},

	_setAllCellsError: function(errorMessage) {
		for (var index = 0; index < STATUS_FIELDS.length; index++) {
			var cell = document.getElementById('zzu-cell-' + STATUS_FIELDS[index].key);
			if (cell) {
				cell.innerHTML = '';
				cell.className = 'td left';
				cell.appendChild(E('em', _('Error')));
			}
		}

		var messageCell = document.getElementById('zzu-cell-msg');
		if (messageCell) {
			messageCell.innerHTML = '';
			messageCell.className = 'td left';
			messageCell.appendChild(E('em', errorMessage));
		}
	},

	_updateCells: function(statusInfo) {
		var hasData = statusInfo != null && statusInfo.data != null &&
			typeof statusInfo.data === 'object';
		var statusData = hasData ? statusInfo.data : {};
		var statusMessage = (statusInfo && statusInfo.msg) ? statusInfo.msg : '';

		for (var index = 0; index < STATUS_FIELDS.length; index++) {
			var fieldKey = STATUS_FIELDS[index].key;
			var cell = document.getElementById('zzu-cell-' + fieldKey);
			if (!cell)
				continue;

			cell.innerHTML = '';
			cell.className = 'td left';

			var fieldValue = hasData ? statusData[fieldKey] : null;
			if (fieldValue != null)
				cell.appendChild(document.createTextNode(String(fieldValue)));
			else
				cell.appendChild(E('em', _('Not found')));
		}

		var messageCell = document.getElementById('zzu-cell-msg');
		if (messageCell) {
			messageCell.innerHTML = '';
			messageCell.className = 'td left';
			messageCell.appendChild(document.createTextNode(statusMessage || '\u2014'));
		}

		var loginStateLabel;
		if (statusInfo && statusInfo.state === 'abnormal')
			loginStateLabel = _('Portal state abnormal');
		else if (statusInfo && statusInfo.state === 'logged_out')
			loginStateLabel = _('Not logged in');
		else if (statusInfo && statusInfo.state === 'logged_in')
			loginStateLabel = _('Online');
		else
			loginStateLabel = _('Info unavailable');

		var heading = document.querySelector('#zzuportal-status h3');
		if (heading)
			heading.textContent = _('User login information') + ' (' + loginStateLabel + ')';
	},

	_runAction: function(rpcCall, actionLabel) {
		var viewInstance = this;

		viewInstance._showMessage(_('%s in progress...').format(actionLabel), false);
		return rpcCall()
			.then(function(response) {
				if (response && response.error)
					throw new Error(response.msg || _('%s failed').format(actionLabel));

				viewInstance._showMessage(
					(response && response.msg) ? response.msg : _('%s complete').format(actionLabel),
					false);
				window.setTimeout(function() {
					viewInstance._refreshStatus();
				}, ACTION_REFRESH_DELAY);
			})
			.catch(function(error) {
				viewInstance._showMessage(
					_('%s failed: ').format(actionLabel) + (error.message || String(error)),
					true);
			});
	},

	_doRefresh: function() {
		return this._refreshStatus();
	},

	_doLogin: function() {
		return this._runAction(callLogin, _('Login'));
	},

	_doLogout: function() {
		return this._runAction(callLogout, _('Logout'));
	},

	_doRelogin: function() {
		var viewInstance = this;
		var actionLabel = _('Change MAC & Re-login');

		if (viewInstance._reloginPollTimer != null) {
			window.clearTimeout(viewInstance._reloginPollTimer);
			viewInstance._reloginPollTimer = null;
		}
		viewInstance._showMessage(_('%s in progress...').format(actionLabel), false);

		return callRelogin()
			.then(function(response) {
				if (response && response.error)
					throw new Error(response.msg || _('%s failed').format(actionLabel));

				viewInstance._showMessage(
					(response && response.msg) ? response.msg : _('%s in progress...').format(actionLabel),
					false);
				viewInstance._scheduleReloginStatusPoll();
			})
			.catch(function(error) {
				viewInstance._showMessage(
					_('%s failed: ').format(actionLabel) + (error.message || String(error)),
					true);
			});
	},

	_scheduleReloginStatusPoll: function() {
		var viewInstance = this;

		if (viewInstance._reloginPollTimer != null)
			window.clearTimeout(viewInstance._reloginPollTimer);
		viewInstance._reloginPollTimer = window.setTimeout(function() {
			viewInstance._reloginPollTimer = null;
			viewInstance._pollReloginStatus();
		}, RELOGIN_POLL_INTERVAL);
	},

	_pollReloginStatus: function() {
		var viewInstance = this;
		var actionLabel = _('Change MAC & Re-login');

		return callGetReloginStatus()
			.then(function(jobStatus) {
				var jobState = jobStatus ? jobStatus.state : 'failed';
				var jobMessage = (jobStatus && jobStatus.msg) ? jobStatus.msg :
					_('%s failed').format(actionLabel);

				if (jobState === 'running') {
					viewInstance._showMessage(jobMessage, false);
					viewInstance._scheduleReloginStatusPoll();
				} else if (jobState === 'completed') {
					viewInstance._showMessage(jobMessage, false);
					window.setTimeout(function() {
						viewInstance._refreshStatus();
					}, ACTION_REFRESH_DELAY);
				} else if (jobState === 'failed') {
					viewInstance._showMessage(jobMessage, true);
				} else {
					viewInstance._refreshStatus();
				}
			})
			.catch(function() {
				viewInstance._showMessage(_('%s in progress...').format(actionLabel), false);
				viewInstance._scheduleReloginStatusPoll();
			});
	},

	_renderActionButtons: function() {
		var viewInstance = this;
		var buttonStyle = 'margin-right: 8px; margin-bottom: 8px;';

		var refreshButton = E('button', {
			'class': 'btn cbi-button cbi-button-reset',
			'style': buttonStyle,
			'click': function() { viewInstance._doRefresh(); }
		}, _('Refresh'));

		var loginButton = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'style': buttonStyle,
			'click': function() { viewInstance._doLogin(); }
		}, _('Login'));

		var logoutButton = E('button', {
			'class': 'btn cbi-button cbi-button-reset',
			'style': buttonStyle,
			'click': function() { viewInstance._doLogout(); }
		}, _('Logout'));

		var reloginButton = E('button', {
			'class': 'btn cbi-button cbi-button-reload',
			'style': buttonStyle,
			'click': function() { viewInstance._doRelogin(); }
		}, _('Change MAC & Re-login'));

		return E('div', {}, [refreshButton, loginButton, logoutButton, reloginButton]);
	},

	_showMessage: function(text, isError) {
		var messageContainer = document.getElementById('zzuportal-status-msg');
		if (!messageContainer)
			return;

		var messageClass = isError ? 'alert-message error' : 'alert-message notice';
		messageContainer.innerHTML = '';
		messageContainer.appendChild(E('div', { 'class': messageClass }, text));
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
