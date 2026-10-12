import 'package:flutter/material.dart';

/// A stylised paper receipt used as a placeholder for captured images.
class ReceiptMock extends StatelessWidget {
  const ReceiptMock({
    super.key,
    this.width = 150,
    this.lineColor = const Color(0xFFE2E6F0),
  });

  final double width;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: _bar(width * 0.5, 8, lineColor)),
          const SizedBox(height: 6),
          Center(child: _bar(width * 0.32, 5, lineColor)),
          const SizedBox(height: 14),
          for (final double f in <double>[1, 0.85, 0.95, 0.7, 0.9, 0.6]) ...<Widget>[
            _bar(width * f * 0.72, 5, lineColor),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Container(height: 1, color: lineColor),
          const SizedBox(height: 10),
          _bar(width * 0.4, 7, lineColor),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: width * 0.6,
              height: 26,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List<Widget>.generate(
                  16,
                  (int i) => Container(
                    width: i % 3 == 0 ? 3 : 1.5,
                    color: lineColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h / 2),
        ),
      );
}
