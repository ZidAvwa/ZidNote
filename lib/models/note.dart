import 'package:flutter/material.dart';

/// Text style of one character: color, font, size, bold.
class TS {
  final int color;
  final String font;
  final double size;
  final bool bold;
  const TS(this.color, this.font, this.size, this.bold);

  static const def = TS(0xFF000000, 'Roboto', 18, false);

  TS copy({int? color, String? font, double? size, bool? bold}) =>
      TS(color ?? this.color, font ?? this.font, size ?? this.size, bold ?? this.bold);

  @override
  bool operator ==(Object o) =>
      o is TS && o.color == color && o.font == font && o.size == size && o.bold == bold;
  @override
  int get hashCode => Object.hash(color, font, size, bold);

  TextStyle get style => TextStyle(
      color: Color(color),
      fontFamily: font,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal);

  String get hex => (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
}

/// A piece of text sharing one style.
class Run {
  final String t;
  final TS s;
  Run(this.t, this.s);

  Map toJson() => {'t': t, 'c': s.color, 'f': s.font, 's': s.size, 'b': s.bold};
  factory Run.fromJson(Map j) =>
      Run(j['t'], TS(j['c'], j['f'], (j['s'] as num).toDouble(), j['b']));
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
