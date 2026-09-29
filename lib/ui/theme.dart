import 'package:flutter/material.dart';

/// Shared look for the menus: dark UI over the sunset palette of Flat Arena.
abstract final class BrawlColors {
  static const background = Color(0xFF14101F);
  static const panel = Color(0xFF231A36);
  static const accent = Color(0xFFFFA24C);
  static const player = Color(0xFF4FC3F7);
  static const text = Colors.white;
  static const muted = Colors.white70;
}

ThemeData brawlTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: BrawlColors.background,
  colorScheme: const ColorScheme.dark(
    primary: BrawlColors.accent,
    onPrimary: Colors.black,
    surface: BrawlColors.panel,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  ),
);
