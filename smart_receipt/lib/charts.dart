import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Simple line chart drawn without third-party packages.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.values,
    required this.labels,
    this.color,
    this.height = 150,
    this.highlightLast = false,
  });

  final List<double> values;
  final List<String> labels;
  final Color? color;
  final double height;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(
              values: values,
              color: color ?? AppColors.navy,
              highlightLast: highlightLast,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final String l in labels)
              Text(
                l,
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.color,
    required this.highlightLast,
  });

  final List<double> values;
  final Color color;
  final bool highlightLast;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    final double maxValue = values.reduce((double a, double b) => a > b ? a : b) * 1.2;
    final double dx = size.width / (values.length - 1);

    final Paint grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final double y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final List<Offset> points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(i * dx, size.height - (values[i] / maxValue) * size.height),
    ];

    final Path area = Path()..moveTo(points.first.dx, size.height);
    for (final Offset p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, size.height)
      ..close();

    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(area, fill);

    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (int i = 0; i < points.length; i++) {
      final bool last = i == points.length - 1;
      final bool emphasize = highlightLast && last;
      canvas.drawCircle(points[i], emphasize ? 5.5 : 3.6, Paint()..color = AppColors.card);
      canvas.drawCircle(
        points[i],
        emphasize ? 5.5 : 3.6,
        Paint()
          ..color = emphasize ? AppColors.orange : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.highlightLast != highlightLast;
}
