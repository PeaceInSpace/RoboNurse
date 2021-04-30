import 'dart:math';

import 'package:flutter/material.dart';

class CircleProgress extends CustomPainter {
  double value;
  bool isCelsius;
  Color progressBarColor;
  CircleProgress(this.value, this.isCelsius,this.progressBarColor);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    int maximumValue =
        isCelsius ? 120 : 248;

    Paint outerCircle = Paint()
      ..strokeWidth = 8
      ..color = Colors.grey[800]
      ..style = PaintingStyle.stroke;

    Paint tempArc = Paint()
      ..strokeWidth = 7
      ..color = this.progressBarColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Paint humidityArc = Paint()
    //   ..strokeWidth = 14
    //   ..color = Colors.tealAccent
    //   ..style = PaintingStyle.stroke
    //   ..strokeCap = StrokeCap.round;

    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = min(size.width / 2, size.height / 2) - 25;
    canvas.drawCircle(center, radius, outerCircle);

    double angle = 2 * pi * (value / maximumValue);

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2,
        angle, false, tempArc);
  }
}