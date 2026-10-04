import 'package:flutter/material.dart';
import 'storage.dart';

/// App-wide theme mode; the MaterialApp listens to this.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode _parse(String s) => switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

void initTheme() => themeMode.value = _parse(loadTheme());

/// [s] is 'system', 'light' or 'dark'.
void setTheme(String s) {
  saveTheme(s);
  themeMode.value = _parse(s);
}
