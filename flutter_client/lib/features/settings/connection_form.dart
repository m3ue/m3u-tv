import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';

/// Form for entering Xtream/M3U connection credentials.
///
/// Mirrors the RN SettingsScreen connection form with server URL,
/// username, and password fields. Password field uses obscureText.
/// Does NOT log passwords.
class ConnectionForm extends StatefulWidget {
  const ConnectionForm({
    super.key,
    required this.onConnect,
    this.isLoading = false,
    this.error,
  });

  /// Called with the entered credentials when the user taps Connect.
  final void Function(UserCredentials credentials) onConnect;

  /// Whether to show a loading indicator instead of the Connect button text.
  final bool isLoading;

  /// Error message to display above the form fields.
  final String? error;

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _validationError = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _validationError = null;
    });

    widget.onConnect(UserCredentials(
      server: server,
      username: username,
      password: password,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayError = _validationError ?? widget.error;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connection Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Enter your Xtream codes details', style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 24),
          if (displayError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                displayError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          TextFormField(
            controller: _serverController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://example.com:8080',
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: widget.isLoading ? null : _handleConnect,
              child: widget.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}