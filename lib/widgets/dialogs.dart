import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Asks for a short text (group name, preset name). Returns null if cancelled.
Future<String?> askText(BuildContext context, String title, {String initial = ''}) {
  final t = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: t, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, t.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message, {String yes = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

/// Picks one color from swatches. With [custom], a last "pick your own" swatch
/// returns -1. Returns null if dismissed.
Future<int?> pickSwatch(BuildContext context, String title, List<int> colors,
        {bool custom = false}) =>
    showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Wrap(children: [
          for (final c in colors)
            GestureDetector(
              onTap: () => Navigator.pop(d, c),
              child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle)),
            ),
          if (custom)
            GestureDetector(
              onTap: () => Navigator.pop(d, -1),
              child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, border: Border.all(color: Colors.grey, width: 2)),
                  child: const Icon(Icons.colorize, size: 20)),
            ),
        ]),
      ),
    );

/// Full color picker: RGB / HSV / HSL value changers plus a hex code input at the bottom.
Future<Color?> pickColorDialog(BuildContext context, Color start) async {
  Color c = start;
  final w = min(300.0, MediaQuery.of(context).size.width - 120);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: c,
          onColorChanged: (v) => c = v,
          enableAlpha: false,
          hexInputBar: true,
          portraitOnly: true,
          colorPickerWidth: w,
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('OK'))],
    ),
  );
  return ok == true ? c : null;
}
