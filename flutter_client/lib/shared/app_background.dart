import 'package:flutter/material.dart';

const BoxDecoration kAppGradientBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1a1528),
      Color(0xFF09090b),
      Color(0xFF09090b),
    ],
    stops: [0.0, 0.45, 1.0],
  ),
);
