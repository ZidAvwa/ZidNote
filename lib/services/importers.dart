import 'dart:convert';
import 'package:archive/archive.dart';
import '../models/note.dart';

String _unx(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Reads color, font, size and bold from a run's <w:rPr> block.
TS _rpr(String rpr) {
  var s = TS.def;
  final c = RegExp(r'<w:color w:val="([0-9A-Fa-f]{6})"').firstMatch(rpr);
  if (c != null) s = s.copy(color: 0xFF000000 | int.parse(c[1]!, radix: 16));
  final f = RegExp(r'<w:rFonts[^>]*?w:ascii="([^"]+)"').firstMatch(rpr);
  if (f != null) s = s.copy(font: f[1]);
  final z = RegExp(r'<w:sz w:val="(\d+)"').firstMatch(rpr);
  if (z != null) s = s.copy(size: int.parse(z[1]!) / 2);
  if (RegExp(r'<w:b\s*/>|<w:b\s+w:val="(?:1|true|on)"').hasMatch(rpr)) {
    s = s.copy(bold: true);
  }
  return s;
}

List<Run> _merge(List<Run> rs) {
  final o = <Run>[];
  for (final r in rs) {
    if (o.isNotEmpty && o.last.s == r.s) {
      o[o.length - 1] = Run(o.last.t + r.t, r.s);
    } else {
      o.add(r);
    }
  }
  return o;
}

/// Parses a .docx (only direct run formatting; styles.xml is ignored).
List<Run> fromDocx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final f = zip.findFile('word/document.xml');
  if (f == null) throw const FormatException('Not a .docx file');
  final xml = utf8.decode(f.content as List<int>);

  final paraRe = RegExp(r'<w:p(?:\s[^>]*)?>(.*?)</w:p>', dotAll: true);
  final runRe = RegExp(r'<w:r(?:\s[^>]*)?>(.*?)</w:r>', dotAll: true);
  final rprRe = RegExp(r'<w:rPr>(.*?)</w:rPr>', dotAll: true);
  final partRe = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>|<w:tab\s*/>|<w:br\s*/>', dotAll: true);

  final out = <Run>[];
  final paras = paraRe.allMatches(xml).toList();
  for (int i = 0; i < paras.length; i++) {
    TS last = TS.def;
    for (final r in runRe.allMatches(paras[i][1]!)) {
      final body = r[1]!;
      final st = _rpr(rprRe.firstMatch(body)?[1] ?? '');
      last = st;
      final b = StringBuffer();
      for (final m in partRe.allMatches(body)) {
        final tag = m[0]!;
        if (tag.startsWith('<w:tab')) {
          b.write('\t');
        } else if (tag.startsWith('<w:br')) {
          b.write('\n');
        } else {
          b.write(_unx(m[1] ?? ''));
        }
      }
      if (b.isNotEmpty) out.add(Run(b.toString(), st));
    }
    if (i < paras.length - 1) out.add(Run('\n', last));
  }
  return _merge(out);
}
