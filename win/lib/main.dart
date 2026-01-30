import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MetaSynxBridgeApp());
}

class MetaSynxBridgeApp extends StatelessWidget {
  const MetaSynxBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MetaSynx Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00D4AA),
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        fontFamily: 'Segoe UI',
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final UserService _userService = UserService();
  String? _relayServer;
  bool _isLoadingUserData = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00D4AA),
              ),
            ),
          );
        }

        // User is logged in
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;

          // If we haven't loaded user data yet, show loading
          if (_relayServer == null && !_isLoadingUserData) {
            _loadUserData(user);
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF00D4AA),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Still loading
          if (_isLoadingUserData) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF00D4AA),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // User data loaded, show home screen
          return HomeScreen(
            relayServer: _relayServer!,
            userEmail: user.email ?? '',
            onSignOut: () => _signOut(user.uid),
          );
        }

        // User is not logged in
        return LoginScreen(
          onLoginSuccess: () {
            // Auth state change will handle navigation
          },
        );
      },
    );
  }

  Future<void> _loadUserData(User user) async {
    setState(() {
      _isLoadingUserData = true;
    });

    try {
      final server = await _userService.getOrAssignRelayServer(user);
      await _userService.updateLastLogin(user);
      
      if (mounted) {
        setState(() {
          _relayServer = server;
          _isLoadingUserData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() {
          // Fallback to default server if Firestore fails
          _relayServer = 'server1.metasynx.io';
          _isLoadingUserData = false;
        });
      }
    }
  }

  Future<void> _signOut(String uid) async {
    // Set signedIn to false before signing out
    await _userService.signOut(uid);
    await FirebaseAuth.instance.signOut();
    setState(() {
      _relayServer = null;
      _isLoadingUserData = false;
    });
  }
}