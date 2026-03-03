'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('camera_access_control',
			_('Camera Access Control – Cameras'),
			_('Add the IP addresses and MAC addresses of cameras to be controlled. ' +
			  'Each camera is controlled independently via its own policies.'));

		s = m.section(form.TypedSection, 'camera', _('Cameras'));
		s.addremove = true;
		s.anonymous = true;

		o = s.option(form.Value, 'name', _('Name'), _('Friendly name for this camera'));
		o.rmempty = false;
		o.placeholder = _('e.g. Front Door Camera');

		o = s.option(form.Value, 'ip', _('IP Address'),
			_('IPv4 address of the camera on the LAN'));
		o.rmempty = false;
		o.datatype = 'ip4addr';
		o.placeholder = '192.168.8.210';

		o = s.option(form.Value, 'mac', _('MAC Address'),
			_('MAC address of the camera (optional, for reference)'));
		o.rmempty = true;
		o.datatype = 'macaddr';
		o.placeholder = 'AA:BB:CC:DD:EE:FF';

		o = s.option(form.Flag, 'enabled', _('Enabled'),
			_('Enable or disable all policies for this camera'));
		o.default = '1';
		o.rmempty = false;

		return m.render();
	}
});
