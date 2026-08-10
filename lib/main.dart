import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android TV: lock to landscape and hide system bars for a 10-foot,
  // full-bleed UI (the manifest also locks orientation; this covers the
  // brief window before the activity's screenOrientation applies).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const RiveStreamApp());
}

class RiveStreamApp extends StatelessWidget {
  const RiveStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiveStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF2E92),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF14121A),
      ),
      home: const HomeShell(),
    );
  }
}
