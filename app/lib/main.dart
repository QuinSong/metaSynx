import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MetaSynxApp());
}

class MetaSynxApp extends StatelessWidget {
  const MetaSynxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MetaSynx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00D4AA),
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E14),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
