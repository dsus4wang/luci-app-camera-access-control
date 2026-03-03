'use strict';
'require view';
'require form';
'require rpc';
'require ui';

var callApplyRules = rpc.declare({
	object: 'luci.camera_access_control',
	method: 'apply',
	expect: { result: 'error' }
});

var callTestAlert = rpc.declare({
	object: 'luci.camera_access_control',
	method: 'test_alert',
	params: [ 'camera_ip', 'camera_name' ],
	expect: { result: 'error' }
});

var callStatus = rpc.declare({
	object: 'luci.camera_access_control',
	method: 'status',
	expect: {}
});

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(status) {
		var m, s, o;

		/* ---- Settings form ---- */
		m = new form.Map('camera_access_control',
			_('Camera Access Control – Settings'),
			_('Global settings for the Camera Access Control plugin. ' +
			  'Configure the DingTalk webhook for real-time video-transmission alerts.'));

		s = m.section(form.NamedSection, 'settings', 'global', _('Alert Settings'));
		s.addremove = false;

		o = s.option(form.Value, 'dingtalk_webhook_url',
			_('DingTalk Webhook URL'),
			_('The incoming webhook URL of your DingTalk robot. ' +
			  'Leave blank to disable alerts. Example: ' +
			  'https://oapi.dingtalk.com/robot/send?access_token=xxx'));
		o.rmempty = true;
		o.placeholder = 'https://oapi.dingtalk.com/robot/send?access_token=...';

		o = s.option(form.Value, 'dingtalk_interval',
			_('Alert Interval (minutes)'),
			_('Minimum number of minutes between successive alerts for the same camera.'));
		o.datatype = 'uinteger';
		o.placeholder = '5';
		o.default = '5';

		/* ---- Status / Actions ---- */
		var view = this;

		return m.render().then(function(mapEl) {
			/* Service status banner */
			var running = status && status.running;
			var statusDiv = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Service Status')),
				E('p', {}, [
					E('strong', {}, _('Cron scheduler: ')),
					running
						? E('span', { 'style': 'color:green' }, _('Active'))
						: E('span', { 'style': 'color:red' },   _('Inactive'))
				])
			]);

			/* Active rules display */
			var rules = (status && status.rules) ? status.rules.replace(/\\n/g, '\n') : '';
			var rulesDiv = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Active nftables Rules')),
				E('pre', {
					'style': 'background:#f4f4f4;padding:8px;border-radius:4px;' +
					         'overflow-x:auto;font-size:12px;max-height:200px;'
				}, rules || _('(no rules / service not running)'))
			]);

			/* Apply button */
			var applyBtn = E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function() {
					applyBtn.disabled = true;
					applyBtn.textContent = _('Applying…');
					callApplyRules().then(function(result) {
						applyBtn.disabled = false;
						applyBtn.textContent = _('Apply Rules Now');
						if (result === 'success') {
							ui.addNotification(null,
								E('p', {}, _('Rules applied successfully.')),
								'info');
						} else {
							ui.addNotification(null,
								E('p', {}, _('Failed to apply rules: ') + result),
								'error');
						}
					});
				}
			}, _('Apply Rules Now'));

			/* Test alert button */
			var testBtn = E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'style': 'margin-left:8px',
				'click': function() {
					testBtn.disabled = true;
					testBtn.textContent = _('Sending…');
					callTestAlert('test-ip', 'Test Camera').then(function(result) {
						testBtn.disabled = false;
						testBtn.textContent = _('Send Test Alert');
						if (result === 'success') {
							ui.addNotification(null,
								E('p', {}, _('Test alert sent successfully.')),
								'info');
						} else {
							ui.addNotification(null,
								E('p', {}, _('Failed to send test alert: ') + result),
								'error');
						}
					});
				}
			}, _('Send Test Alert'));

			var actionsDiv = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Actions')),
				applyBtn,
				testBtn
			]);

			mapEl.appendChild(statusDiv);
			mapEl.appendChild(rulesDiv);
			mapEl.appendChild(actionsDiv);

			return mapEl;
		});
	}
});
