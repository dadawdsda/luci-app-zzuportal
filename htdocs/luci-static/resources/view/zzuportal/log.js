'use strict';
'require poll';
'require rpc';
'require view';

var callGetLog = rpc.declare({
	object: 'luci.zzuportal',
	method: 'log',
	timeout: 30000
});

return view.extend({
	load: function() {
		return callGetLog();
	},

	render: function(initialData) {
		var logOutput = E('pre', {
			'class': 'zzuportal-log',
			'style': 'box-sizing:border-box;width:100%;min-height:360px;max-height:65vh;overflow:auto;padding:12px;border:1px solid #ccc;background:#111;color:#eee;white-space:pre-wrap;word-break:break-word;'
		});
		var status = E('span', {
			'class': 'zzuportal-log-status',
			'style': 'min-width:12em;line-height:2.3em;'
		});

		function updateLog(response) {
			if (response && !response.error) {
				logOutput.textContent = response.log || _('No zzuportal log entries.');
				status.textContent = '';
			} else {
				status.textContent = (response && response.msg) ? response.msg : _('Failed to read system log.');
			}
		}

		function refreshLog(event) {
			if (event)
				event.preventDefault();
			return callGetLog().then(updateLog).catch(function(error) {
				status.textContent = error.message || String(error);
			});
		}

		updateLog(initialData);
		poll.add(refreshLog, 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('ZZU Portal Log')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'display:flex;align-items:center;gap:10px;min-height:2.3em;margin-bottom:8px;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': refreshLog
					}, _('Refresh')),
					status
				]),
				logOutput
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
