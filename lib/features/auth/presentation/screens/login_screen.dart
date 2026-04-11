import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/router/app_router.dart' show authNotifier;
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/features/auth/data/auth_api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _locCodeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;

  final _authService = AuthApiService(ApiClient());

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final err = await _authService.login(
      _locCodeCtrl.text,
      _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      setState(() => _error = err);
    } else {
      authNotifier.onChange();
    }
  }

  @override
  void dispose() {
    _locCodeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WakulimaColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Logo
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: WakulimaColors.primary700,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.water_drop, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('WAKULIMA',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: WakulimaColors.primary700,
                      letterSpacing: 2,
                    )),
                  Text('Dairy Platform',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      color: WakulimaColors.inkSoft,
                    )),
                ]),
              ]),

              const SizedBox(height: 48),
              const Text('Welcome back',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 28,
                  fontWeight: FontWeight.w700, color: WakulimaColors.ink,
                  letterSpacing: -0.5,
                )),
              const SizedBox(height: 6),
              const Text('Sign in with your location code',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 15,
                  color: WakulimaColors.inkSoft,
                )),
              const SizedBox(height: 36),

              Form(
                key: _formKey,
                child: Column(children: [
                  // Error banner
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            size: 18, color: WakulimaColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              color: WakulimaColors.error,
                            )),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Location Code
                  TextFormField(
                    controller: _locCodeCtrl,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Location Code',
                      hintText: 'e.g. AG002',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Location code is required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Password
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Password is required' : null,
                  ),
                  const SizedBox(height: 28),

                  // Sign In button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                          : const Text('Sign In'),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 40),
              Center(
                child: Text('Version 3.1.118',
                  style: TextStyle(fontSize: 12, color: WakulimaColors.inkMuted)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
