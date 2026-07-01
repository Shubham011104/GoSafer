import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // Initially show the login screen
  bool _showLogin = true;

  void _toggleView() {
    setState(() {
      _showLogin = !_showLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return LoginScreen(onToggle: _toggleView);
    } else {
      return RegisterScreen(onToggle: _toggleView);
    }
  }
}
