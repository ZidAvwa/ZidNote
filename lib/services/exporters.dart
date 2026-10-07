import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note.dart';
import 'storage.dart';

/// "abc<#111111,Roboto,18,biu,h=FFFF00> ..." — each tag follows the text it styles.
/// Fields after the color: font, size, flags (b i u s), h=RRGGBB highlight.
String toColorTxt(List<Run> runs) {
  final b = StringBuffer();
  for (final r in runs) {
    final s = r.s;
    final tag = '<#${s.hex},${s.font},${s.size.round()}'
        '${s.flags.isEmpty ? '' : ',${s.flags}'}'
        '${s.highlight == 0 ? '' : ',h=${s.hlHex}'}>';
    final parts = r.t.split('\n');
    for (int k = 0; k < parts.length; k++) {
      if (parts[k].isNotEmpty) b.write('${parts[k]}$tag');
      if (k < parts.length - 1) b.write('\n');
    }
  }
  return b.toString();
}

TS _tagStyle(String hex, String extra) {
  final f = extra.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  var s = TS.def.copy(color: 0xFF000000 | int.parse(hex, radix: 16));
  bool fontSet = false;
  for (int i = 0; i < f.length; i++) {
    final t = f[i];
    final n = double.tryParse(t);
    final h = RegExp(r'^h=([0-9a-fA-F]{6})$').firstMatch(t);
    if (n != null) {
      s = s.copy(size: n);
    } else if (h != null) {
      s = s.copy(highlight: 0xFF000000 | int.parse(h[1]!, radix: 16));
    } else if (i > 0 && RegExp(r'^[biusBIUS]+$').hasMatch(t)) {
      final l = t.toLowerCase();
      s = s.copy(
          bold: l.contains('b'),
          italic: l.contains('i'),
          underline: l.contains('u'),
          strike: l.contains('s'));
    } else if (!fontSet) {
      s = s.copy(font: t);
      fontSet = true;
    }
  }
  return s;
}

/// Reads the format above. Accepts '#' or '$' before the hex code.
List<Run> fromColorTxt(String src) {
  final re = RegExp(r'<[#$]([0-9a-fA-F]{6})((?:\s*,[^,>]*)*)\s*>');
  final runs = <Run>[];
  int last = 0;
  for (final m in re.allMatches(src)) {
    final seg = src.substring(last, m.start);
    if (seg.isNotEmpty) runs.add(Run(seg, _tagStyle(m[1]!, m[2] ?? '')));
    last = m.end;
  }
  if (last < src.length) runs.add(Run(src.substring(last), TS.def));
  return runs;
}

String _x(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// .docx (a zip of XML files) keeping color, font, size, bold, italic, underline,
/// strikethrough and highlight. Photos and drawings are added after the text.
Future<List<int>> toDocx(Note n) async {
  const ns = 'http://schemas.openxmlformats.org/';
  final body = StringBuffer(
      '<w:p><w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t>${_x(n.title)}</w:t></w:r></w:p><w:p>');
  for (final r in n.runs) {
    final s = r.s;
    final rpr = '<w:rFonts w:ascii="${_x(s.font)}" w:hAnsi="${_x(s.font)}"/>'
        '${s.bold ? '<w:b/>' : ''}${s.italic ? '<w:i/>' : ''}${s.strike ? '<w:strike/>' : ''}'
        '<w:color w:val="${s.hex}"/><w:sz w:val="${(s.size * 2).round()}"/>'
        '${s.underline ? '<w:u w:val="single"/>' : ''}'
        '${s.highlight == 0 ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="${s.hlHex}"/>'}';
    final parts = r.t.split('\n');
    for (int k = 0; k < parts.length; k++) {
      if (parts[k].isNotEmpty) {
        body.write('<w:r><w:rPr>$rpr</w:rPr>'
            '<w:t xml:space="preserve">${_x(parts[k])}</w:t></w:r>');
      }
      if (k < parts.length - 1) body.write('</w:p><w:p>');
    }
  }
  body.write('</w:p>');

  // photos and drawings
  final media = <String, List<int>>{};
  final rels = StringBuffer();
  final exts = <String>{};
  int k = 0;
  for (final name in n.images) {
    final f = File(imagePath(name));
    if (!await f.exists()) continue;
    final bytes = await f.readAsBytes();
    int w = 800, h = 600;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final fr = await codec.getNextFrame();
      w = fr.image.width;
      h = fr.image.height;
    } catch (_) {}
    k++;
    var ext = name.split('.').last.toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    exts.add(ext);
    media['word/media/image$k.$ext'] = bytes;
    rels.write('<Relationship Id="rIdImg$k" Type="${ns}officeDocument/2006/relationships/image" '
        'Target="media/image$k.$ext"/>');
    var cx = w * 9525, cy = h * 9525; // EMU at 96 dpi
    const maxCx = 5486400; // 6 inches
    if (cx > maxCx) {
      cy = (cy * maxCx / cx).round();
      cx = maxCx;
    }
    body.write('<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$k" name="Picture $k"/>'
        '<a:graphic xmlns:a="${ns}drawingml/2006/main">'
        '<a:graphicData uri="${ns}drawingml/2006/picture">'
        '<pic:pic xmlns:pic="${ns}drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$k" name="image$k"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rIdImg$k"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
  }

  const mimes = {'png': 'image/png', 'jpg': 'image/jpeg', 'webp': 'image/webp', 'gif': 'image/gif'};
  final defaults = exts
      .map((e) => '<Default Extension="$e" ContentType="${mimes[e] ?? 'application/octet-stream'}"/>')
      .join();

  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="${ns}package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>$defaults<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="${ns}package/2006/relationships"><Relationship Id="rId1" Type="${ns}officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="${ns}wordprocessingml/2006/main" xmlns:r="${ns}officeDocument/2006/relationships" xmlns:wp="${ns}drawingml/2006/wordprocessingDrawing"><w:body>$body</w:body></w:document>',
    if (k > 0)
      'word/_rels/document.xml.rels':
          '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="${ns}package/2006/relationships">$rels</Relationships>',
  };
  final ar = Archive();
  files.forEach((path, v) {
    final d = utf8.encode(v);
    ar.addFile(ArchiveFile(path, d.length, d));
  });
  media.forEach((path, b) => ar.addFile(ArchiveFile(path, b.length, b)));
  return ZipEncoder().encode(ar)!;
}

/// Writes a temp file and opens the share sheet (pick "Save to device", Drive, etc.).
Future<void> shareFile(String name, List<int> bytes, String mime) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(f.path, mimeType: mime)]);
}

String safeName(String t) =>
    (t.trim().isEmpty ? 'note' : t.trim()).replaceAll(RegExp(r'[^\w\- ]'), '_');

/// Opens the system "save as" dialog so the user picks a device folder.
/// Returns the saved path, or null if cancelled.
Future<String?> saveToDevice(String name, List<int> bytes) => FilePicker.platform
    .saveFile(dialogTitle: 'Save to…', fileName: name, bytes: Uint8List.fromList(bytes));
