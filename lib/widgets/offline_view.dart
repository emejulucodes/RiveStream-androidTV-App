import 'package:flutter/material.dart';

import 'tv_button.dart';

/// Full-screen connection-error state with an autofocused Retry action so
/// it is reachable purely from a D-pad remote (no touch).
class OfflineView extends StatelessWidget {
  const OfflineView({
    super.key,
    required this.onRetry,
    this.onSettings,
    this.message = 'Can\'t reach RiveStream right now.',
  });

  final VoidCallback onRetry;
  final VoidCallback? onSettings;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14121A),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.white70),
          const SizedBox(height: 24),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your network connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvButton(
                icon: Icons.refresh_rounded,
                label: 'Retry',
                onPressed: onRetry,
                autofocus: true,
              ),
              if (onSettings != null) ...[
                const SizedBox(width: 16),
                TvButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onPressed: onSettings!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
