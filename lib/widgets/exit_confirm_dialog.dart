import 'package:flutter/material.dart';

import 'tv_button.dart';

/// What the user chose in [showExitConfirmDialog].
enum ExitChoice { exit, refresh, settings, cancel }

/// Confirmation shown when Back is pressed with no page history left.
///
/// Native key interception must be disabled while this is up (the caller
/// handles that) so Flutter's own focus traversal drives the buttons --
/// otherwise the D-pad would still be driving the page underneath.
Future<ExitChoice> showExitConfirmDialog(BuildContext context) async {
  final choice = await showDialog<ExitChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => const _ExitConfirmDialog(),
  );
  return choice ?? ExitChoice.cancel;
}

class _ExitConfirmDialog extends StatelessWidget {
  const _ExitConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C1926),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leave RiveStream?',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'You can reload the page, open settings, or close the app.',
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  // Cancel is autofocused: an accidental Back press should
                  // never be one more click away from quitting.
                  Expanded(
                    child: TvButton(
                      autofocus: true,
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(ExitChoice.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TvButton(
                      icon: Icons.refresh_rounded,
                      label: 'Refresh',
                      onPressed: () => Navigator.of(context).pop(ExitChoice.refresh),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TvButton(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      onPressed: () => Navigator.of(context).pop(ExitChoice.settings),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TvButton(
                      icon: Icons.exit_to_app_rounded,
                      label: 'Exit',
                      onPressed: () => Navigator.of(context).pop(ExitChoice.exit),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
