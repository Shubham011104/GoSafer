import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main_wrapper.dart';
import 'auth_page.dart';
import '../../services/permission_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Request critical safety permissions immediately on startup
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await PermissionService.requestInitialPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If the connection is active, check the auth state
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          
          if (user == null) {
            return const AuthPage();
          } else {
            return const MainWrapper();
          }
        }
        
        // While waiting for the connection, show a loading indicator
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
