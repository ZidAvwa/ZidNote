import 'package:flutter/material.dart';
import '../models/note.dart';

/// TextEditingController that keeps one style per character.
class RichCtl extends TextEditingController {
  List<TS> chars = [];
  TS pen = TS.def; // style for newly typed text when nothing is selected
  String _old = '';
  int _off = -1;

  RichCtl() {
    addListener(_onChange);
  }

  void load(List<Run> runs) {
    chars = [for (final r in runs) ...List.filled(r.t.length, r.s)];
    _old = runs.map((r) => r.t).join();
    value = TextEditingValue(text: _old);
  }

  void _onChange() {
    if (text != _old) {
      _sync();
      _off = selection.baseOffset;
      return;
    }
    // Cursor moved: typing continues with the style of the character before it.
    final s = selection;
    if (s.isCollapsed && s.baseOffset >= 0 && s.baseOffset != _off) {
      _off = s.baseOffset;
      final i = s.baseOffset > 0 ? s.baseOffset - 1 : 0;
      if (i < chars.length) pen = chars[i];
    }
  }

  // Keeps `chars` aligned with the text after every edit (insert/delete/paste).
  void _sync() {
    final n = text;
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

  /// Style shown in the selectors: of the selection, or of the typing pen.
  TS get current {
    final s = selection;
    if (s.isValid && !s.isCollapsed && s.start < chars.length) return chars[s.start];
    return pen;
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
