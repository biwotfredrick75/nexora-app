import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/router/app_router.dart' show authNotifier;
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/app_constants.dart';
import 'package:wakulima/features/auth/data/auth_api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Box _settings;
  final _stationCtrl = TextEditingController();
  final _agentCtrl   = TextEditingController();
  final _priceCtrl   = TextEditingController();
  final _apiCtrl     = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = Hive.box(AppConstants.settingsBox);
    _stationCtrl.text = _settings.get('station', defaultValue: '') as String;
    _agentCtrl.text   = _settings.get('agent',   defaultValue: '') as String;
    _priceCtrl.text   = (_settings.get('default_price', defaultValue: 50.0) as double).toString();
    _apiCtrl.text     = _settings.get('api_url',  defaultValue: AppConstants.apiBaseUrl) as String;
  }

  @override
  void dispose() {
    _stationCtrl.dispose(); _agentCtrl.dispose();
    _priceCtrl.dispose();   _apiCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _settings.put('station', _stationCtrl.text.trim());
    _settings.put('agent',   _agentCtrl.text.trim());
    _settings.put('default_price', double.tryParse(_priceCtrl.text) ?? 50.0);
    _settings.put('api_url', _apiCtrl.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'),
          backgroundColor: WakulimaColors.success));
  }

  bool _loggingOut = false;

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: 'Poppins', color: WakulimaColors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out',
                style: TextStyle(fontFamily: 'Poppins',
                    color: WakulimaColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loggingOut = true);

    // Revoke token on backend + clear local session
    await AuthApiService(ApiClient()).logout();

    // Notify the router — redirect fires, sends to /login
    authNotifier.onChange();
  }

  @override
  Widget build(BuildContext context) {
    final user = Map<String, dynamic>.from(
        Hive.box(AppConstants.authBox).get('user') ?? <String, dynamic>{});

    return Scaffold(
      backgroundColor: WakulimaColors.cream,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600,
              color: WakulimaColors.primary700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          _card([
            _label('Account'),
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: WakulimaColors.primary100,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    AppFormatters.initials(user['name'] as String? ?? 'WK'),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w700, color: WakulimaColors.primary700),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['name'] as String? ?? 'User',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                        fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
                  Text('Role: ${user['role'] ?? 'agent'}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: WakulimaColors.inkMuted)),
                ],
              )),
            ]),
          ]),

          const SizedBox(height: 12),

          _card([
            _label('Collection Point'),
            _field('Station Name', _stationCtrl, hint: 'e.g. Nakuru MCC Central'),
            _field('Agent Name',   _agentCtrl,   hint: 'Your full name'),
            _field('Default Price / kg (KSh)', _priceCtrl,
                hint: '50', keyboard: TextInputType.number),
          ]),

          const SizedBox(height: 12),

          _card([
            _label('Backend API'),
            _field('API Base URL', _apiCtrl, hint: AppConstants.apiBaseUrl),
            const SizedBox(height: 2),
            const Text('Leave default unless using a custom server.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted)),
          ]),

          const SizedBox(height: 12),

          _card([
            _label('Bluetooth Scale'),
            _toggle('Auto-fill weight', 'Fill form when stable reading detected', 'ble_autofill', true),
            _toggle('Haptic on stable', 'Vibrate when scale reading stabilises', 'ble_haptic', true),
          ]),

          const SizedBox(height: 12),

          _card([
            _label('Data'),
            _item(Icons.cloud_sync_outlined, 'Sync now', 'Force sync offline queue', () {}),
            _item(Icons.download_outlined, 'Export CSV', 'Download all records', () {}),
            _item(Icons.delete_outline, 'Clear cache', 'Remove synced data only',
                () {}, danger: true),
          ]),

          const SizedBox(height: 12),

          _card([
            _label('About'),
            _item(Icons.info_outline, 'Version', AppConstants.appVersion, null),
            _item(Icons.business_outlined, 'App', AppConstants.appName, null),
          ]),

          const SizedBox(height: 20),

          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.logout),
              label: Text(_loggingOut ? 'Signing out…' : 'Sign Out',
                  style: const TextStyle(fontFamily: 'Poppins')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: WakulimaColors.error),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WakulimaColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(t, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
        fontWeight: FontWeight.w700, color: WakulimaColors.inkSoft, letterSpacing: 0.6)),
  );

  Widget _field(String label, TextEditingController c,
      {String hint = '', TextInputType keyboard = TextInputType.text}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: c, keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint)),
    );

  Widget _toggle(String title, String sub, String key, bool def) {
    final val = _settings.get(key, defaultValue: def) as bool;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
              fontWeight: FontWeight.w500, color: WakulimaColors.ink)),
          Text(sub, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: WakulimaColors.inkMuted)),
        ])),
        Switch(value: val, activeColor: WakulimaColors.primary700,
            onChanged: (v) { _settings.put(key, v); setState(() {}); }),
      ]),
    );
  }

  Widget _item(IconData icon, String title, String sub,
      VoidCallback? onTap, {bool danger = false}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 20,
              color: danger ? WakulimaColors.error : WakulimaColors.inkSoft),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w500,
                color: danger ? WakulimaColors.error : WakulimaColors.ink)),
            Text(sub, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                color: WakulimaColors.inkMuted)),
          ])),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, size: 18,
                color: WakulimaColors.inkMuted),
        ]),
      ),
    );
}
