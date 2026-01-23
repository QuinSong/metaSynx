import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
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
      home: const HomeScreen(),
    );
  }
}
