import 'package:flutter/material.dart';

/// A D-pad-friendly button whose background and border swap when it gains
/// remote/keyboard focus. The default Material focus indication is a subtle
/// overlay tint that is unreadable from across a room, so focus is made
/// unmistakable here instead.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.alignment = Alignment.center,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 18)),
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        alignment: alignment,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? const Color(0xFFFF2E92)
              : const Color(0xFF2A2733),
        ),
        shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: states.contains(WidgetState.focused)
                ? const BorderSide(color: Colors.white, width: 2)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
