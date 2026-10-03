import 'package:flutter/material.dart';

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

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;

/// Picks one color from a list of swatches. Returns null if dismissed.
Future<int?> pickSwatch(BuildContext context, String title, List<int> colors) =>
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
        ]),
      ),
    );
