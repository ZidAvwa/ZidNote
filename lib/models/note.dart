import 'package:flutter/material.dart';

/// Text style of one character.
class TS {
  final int color;
  final String font;
  final double size;
  final bool bold, italic, underline, strike;
  final int highlight; // 0 = none, else ARGB background color

  const TS(this.color, this.font, this.size, this.bold,
      [this.italic = false, this.underline = false, this.strike = false, this.highlight = 0]);

  static const def = TS(0xFF000000, 'Roboto', 18, false);

  TS copy(
          {int? color,
          String? font,
          double? size,
          bool? bold,
          bool? italic,
          bool? underline,
          bool? strike,
          int? highlight}) =>
      TS(
          color ?? this.color,
          font ?? this.font,
          size ?? this.size,
          bold ?? this.bold,
          italic ?? this.italic,
          underline ?? this.underline,
          strike ?? this.strike,
          highlight ?? this.highlight);

  @override
  bool operator ==(Object o) =>
      o is TS &&
      o.color == color &&
      o.font == font &&
      o.size == size &&
      o.bold == bold &&
      o.italic == italic &&
      o.underline == underline &&
      o.strike == strike &&
      o.highlight == highlight;
  @override
  int get hashCode =>
      Object.hash(color, font, size, bold, italic, underline, strike, highlight);

  /// [ink] replaces the default black on dark backgrounds (display only).
  TextStyle styleOn([Color? ink]) => TextStyle(
        color: (ink != null && color == 0xFF000000) ? ink : Color(color),
        fontFamily: font,
        fontSize: size,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (underline) TextDecoration.underline,
          if (strike) TextDecoration.lineThrough,
        ]),
        backgroundColor: highlight == 0 ? null : Color(highlight),
      );

  TextStyle get style => styleOn();

  String get hex => (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  String get hlHex => (highlight & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// Letters used by the colored .txt format: b i u s
  String get flags =>
      '${bold ? 'b' : ''}${italic ? 'i' : ''}${underline ? 'u' : ''}${strike ? 's' : ''}';
}

/// White "ink" for default-black text on dark backgrounds, else null (keep as saved).
Color? autoInk(BuildContext context, int bg) {
  final dark = bg == 0
      ? Theme.of(context).brightness == Brightness.dark
      : Color(bg).computeLuminance() < 0.4;
  return dark ? Colors.white : null;
}

/// A piece of text sharing one style.
class Run {
  final String t;
  final TS s;
  Run(this.t, this.s);

  Map toJson() => {
        't': t,
        'c': s.color,
        'f': s.font,
        's': s.size,
        'b': s.bold,
        'i': s.italic,
        'u': s.underline,
        'x': s.strike,
        'h': s.highlight,
      };

  factory Run.fromJson(Map j) => Run(
      j['t'],
      TS(j['c'], j['f'], (j['s'] as num).toDouble(), j['b'], j['i'] ?? false, j['u'] ?? false,
          j['x'] ?? false, j['h'] ?? 0));
}

class Note {
  String id, title, group; // group '' = no group
  bool pinned; // pinned notes stay on top whatever the sort
  int bg; // note background color (ARGB), 0 = default
  int modified; // ms since epoch
  int deletedAt; // 0 = normal note, else ms when moved to trash
  List<Run> runs;

  Note(this.id, this.title, this.runs,
      [this.group = '', this.pinned = false, this.bg = 0, int? modified, this.deletedAt = 0])
      : modified = modified ?? (int.tryParse(id) ?? 0);

  int get created => int.tryParse(id) ?? 0; // the id is the creation time
  String get plain => runs.map((r) => r.t).join();

  Map toJson() => {
        'id': id,
        'title': title,
        'group': group,
        'pinned': pinned,
        'bg': bg,
        'modified': modified,
        'deletedAt': deletedAt,
        'runs': runs.map((r) => r.toJson()).toList()
      };

  factory Note.fromJson(Map j) => Note(
      j['id'],
      j['title'],
      (j['runs'] as List).map((r) => Run.fromJson(r)).toList(),
      j['group'] ?? '',
      j['pinned'] ?? false,
      j['bg'] ?? 0,
      j['modified'],
      j['deletedAt'] ?? 0);
}
