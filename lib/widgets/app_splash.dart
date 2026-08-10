import 'package:flutter/material.dart';

/// Shown while the WebView is created and its first page load is in
/// flight, over the top of the (already-loading) WebView underneath so
/// that loading is "warmed" during the splash rather than started after it.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14121A),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icon/app_icon.png', width: 140, height: 140),
          const SizedBox(height: 28),
          const Text(
            'RiveStream',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFFF2E92)),
          ),
        ],
      ),
    );
  }
}
