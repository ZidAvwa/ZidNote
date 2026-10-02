import 'package:flutter/material.dart';
import '../models/note.dart';

/// TextEditingController that keeps one style per character.
class RichCtl extends TextEditingController {
  List<TS> chars = [];
  TS pen = TS.def; // style for newly typed text when nothing is selected
  String _old = '';

  RichCtl() {
    addListener(_sync);
  }

  void load(List<Run> runs) {
    chars = [for (final r in runs) ...List.filled(r.t.length, r.s)];
    _old = runs.map((r) => r.t).join();
    value = TextEditingValue(text: _old);
  }

  // Keeps `chars` aligned with the text after every edit (insert/delete/paste).
  void _sync() {
    final n = text;
    if (n == _old) return;
    int p = 0;
    while (p < _old.length && p < n.length && _old[p] == n[p]) {
      p++;
    }
    int s = 0;
    while (s < _old.length - p &&
        s < n.length - p &&
        _old[_old.length - 1 - s] == n[n.length - 1 - s]) {
      s++;
    }
    chars.removeRange(p, _old.length - s);
    chars.insertAll(p, List.filled(n.length - s - p, pen));
    _old = n;
  }

  /// Applies [f] to the selected text, or to the typing style if nothing is selected.
  void apply(TS Function(TS) f) {
    final sel = selection;
    if (sel.isCollapsed) {
      pen = f(pen);
    } else {
      for (int i = sel.start; i < sel.end && i < chars.length; i++) {
        chars[i] = f(chars[i]);
      }
    }
    notifyListeners();
  }

  List<Run> runs() {
    final out = <Run>[];
    for (int i = 0; i < text.length; i++) {
      if (out.isNotEmpty && out.last.s == chars[i]) {
        out[out.length - 1] = Run(out.last.t + text[i], chars[i]);
      } else {
        out.add(Run(text[i], chars[i]));
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context, TextStyle? style, required bool withComposing}) {
    return TextSpan(children: [for (final r in runs()) TextSpan(text: r.t, style: r.s.style)]);
  }
}
