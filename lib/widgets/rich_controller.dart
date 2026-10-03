import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';

/// A saved state for undo/redo: text + per-character styles + cursor.
class _Snap {
  final String text;
  final List<TS> chars;
  final TextSelection sel;
  _Snap(this.text, this.chars, this.sel);
}

/// TextEditingController that keeps one style per character, with undo/redo.
class RichCtl extends TextEditingController {
  List<TS> chars = [];
  TS pen = TS.def; // style for newly typed text when nothing is selected
  String _old = '';
  int _off = -1;

  // ---- undo / redo ----
  static const _maxUndo = 100;
  final List<_Snap> _undo = [], _redo = [];
  late _Snap _base; // state before the current group of typing
  bool _grouping = false;
  Timer? _timer;

  static final _prefixRe = RegExp(r'^(?:• |\d+\. |[☐☑] )');

  RichCtl() {
    _base = _snap();
    addListener(_onChange);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  _Snap _snap() => _Snap(text, List.of(chars), selection);

  /// Loads a note (clears the undo history).
  void load(List<Run> runs) {
    chars = [for (final r in runs) ...List.filled(r.t.length, r.s)];
    _old = runs.map((r) => r.t).join();
    value = TextEditingValue(text: _old);
    _timer?.cancel();
    _grouping = false;
    _undo.clear();
    _redo.clear();
    _base = _snap();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Typing is grouped: edits within 700 ms become one undo step.
  void _touch() {
    if (!_grouping) {
      _undo.add(_base);
      _redo.clear();
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _grouping = true;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () {
      _grouping = false;
      _base = _snap();
    });
  }

  /// Style / list changes are always their own undo step.
  void _discrete(void Function() op) {
    _timer?.cancel();
    _grouping = false;
    _base = _snap();
    _undo.add(_base);
    _redo.clear();
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    op();
    _base = _snap();
  }

  void _closeGroup() {
    _timer?.cancel();
    if (_grouping) {
      _grouping = false;
      _base = _snap();
    }
  }

  void _restore(_Snap s) {
    chars = List.of(s.chars);
    _old = s.text; // set first so the listener does not record this as an edit
    _off = s.sel.baseOffset;
    _base = s;
    value = TextEditingValue(text: s.text, selection: s.sel);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _closeGroup();
    _redo.add(_snap());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _closeGroup();
    _undo.add(_snap());
    _restore(_redo.removeLast());
  }

  // ---- editing ----

  void _onChange() {
    if (text != _old) {
      _touch();
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

  /// Style shown in the toolbar: of the selection, or of the typing pen.
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
      _discrete(() {
        for (int i = sel.start; i < sel.end && i < chars.length; i++) {
          chars[i] = f(chars[i]);
        }
      });
    }
    notifyListeners();
  }

  /// Replaces the whole content (undoable).
  void replaceRuns(List<Run> runs) => _discrete(() {
        chars = [for (final r in runs) ...List.filled(r.t.length, r.s)];
        _old = runs.map((r) => r.t).join();
        value = TextEditingValue(text: _old);
      });

  /// Lists: kind is 'none', 'bullet', 'number' or 'check'.
  /// Works on every line touched by the selection; the markers are plain text,
  /// so they export to .docx / .txt as they are.
  void setList(String kind) {
    final t = text;
    final sel = selection.isValid ? selection : const TextSelection.collapsed(offset: 0);
    final a = sel.start == 0 ? 0 : t.lastIndexOf('\n', sel.start - 1) + 1;
    final endRef = (sel.end > sel.start && t[sel.end - 1] == '\n') ? sel.end - 1 : sel.end;
    int e = t.indexOf('\n', endRef);
    if (e < 0) e = t.length;

    final lines = t.substring(a, e).split('\n');
    final nt = StringBuffer();
    final nc = <TS>[];
    int pos = a, n = 1, firstOld = 0, firstNew = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = _prefixRe.firstMatch(line);
      final plen = m?.end ?? 0;
      final TS st = line.length > plen ? chars[pos + plen] : (line.isNotEmpty ? chars[pos] : pen);
      final String pre = switch (kind) {
        'bullet' => '• ',
        'number' => '${n++}. ',
        'check' => m?[0] == '☑ ' ? '☑ ' : '☐ ',
        _ => '',
      };
      if (i == 0) {
        firstOld = plen;
        firstNew = pre.length;
      }
      nt.write(pre);
      nc.addAll(List.filled(pre.length, st));
      nt.write(line.substring(plen));
      nc.addAll(chars.sublist(pos + plen, pos + line.length));
      if (i < lines.length - 1) {
        nt.write('\n');
        nc.add(chars[pos + line.length]);
      }
      pos += line.length + 1;
    }

    final newT = t.replaceRange(a, e, nt.toString());
    if (newT == t) return;
    final TextSelection ns;
    if (sel.isCollapsed) {
      final rel = sel.start - a;
      final nrel = rel <= firstOld ? firstNew : rel - firstOld + firstNew;
      ns = TextSelection.collapsed(offset: a + nrel);
    } else {
      ns = TextSelection(baseOffset: a, extentOffset: a + nt.length);
    }
    _discrete(() {
      chars.replaceRange(a, e, nc);
      _old = newT;
      _off = ns.baseOffset;
      value = TextEditingValue(text: newT, selection: ns);
    });
  }

  /// Flips ☐ / ☑ on the line that has the cursor.
  void toggleCheck() {
    final t = text;
    final i = selection.isValid ? selection.start : 0;
    final a = i == 0 ? 0 : t.lastIndexOf('\n', i - 1) + 1;
    if (a + 1 >= t.length) return;
    final ch = t[a];
    if ((ch != '☐' && ch != '☑') || t[a + 1] != ' ') return;
    final newT = t.replaceRange(a, a + 1, ch == '☐' ? '☑' : '☐');
    _discrete(() {
      _old = newT; // same length and style, so `chars` stays valid
      value = value.copyWith(text: newT);
    });
  }

  List<Run> runs() {
    final out = <Run>[];
    final t = text;
    int start = 0;
    for (int i = 1; i <= t.length; i++) {
      if (i == t.length || chars[i] != chars[start]) {
        out.add(Run(t.substring(start, i), chars[start]));
        start = i;
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

/// Pressing Enter on a list line continues the list (next number / bullet / box).
/// Pressing Enter on an empty list item ends the list.
class ListContinue extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final o = old.text, n = nv.text;
    final c = nv.selection.baseOffset;
    final typedEnter = n.length == o.length + 1 &&
        nv.selection.isCollapsed &&
        c > 0 &&
        n[c - 1] == '\n' &&
        o == n.replaceRange(c - 1, c, '');
    if (!typedEnter) return nv;

    final ls = c - 1 == 0 ? 0 : n.lastIndexOf('\n', c - 2) + 1;
    final line = n.substring(ls, c - 1);
    final m = RegExp(r'^(?:• |(\d+)\. |[☐☑] )').firstMatch(line);
    if (m == null) return nv;

    if (line.length == m.end) {
      // empty item: remove its marker and the new line
      return TextEditingValue(
          text: n.replaceRange(ls, c, ''), selection: TextSelection.collapsed(offset: ls));
    }
    final p = m[1] != null
        ? '${int.parse(m[1]!) + 1}. '
        : (line.startsWith('•') ? '• ' : '☐ ');
    return TextEditingValue(
        text: n.replaceRange(c, c, p), selection: TextSelection.collapsed(offset: c + p.length));
  }
}
