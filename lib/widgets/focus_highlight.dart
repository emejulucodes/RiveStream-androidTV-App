import 'package:flutter/material.dart';

/// The tab-mode focus indicator, drawn by Flutter on top of the WebView.
///
/// The page's own CSS `:focus` outline is not sufficient on this site: the
/// navbar links are ~21x27px and live inside a clipped scroller, so the
/// outline is cropped or simply too small to see from across a room. Drawing
/// it here also guarantees it sits above every page stacking context.
class FocusHighlight extends StatelessWidget {
  const FocusHighlight({super.key, required this.rect, this.label});

  /// Target rect in *viewport fractions* (0..1), as reported by the page.
  final Rect rect;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Inflated slightly so the ring sits just outside the element.
        final box = Rect.fromLTWH(
          rect.left * w,
          rect.top * h,
          rect.width * w,
          rect.height * h,
        ).inflate(4);

        return IgnorePointer(
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOutCubic,
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF2E92), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2E92).withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
