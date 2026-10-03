import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note.dart';

/// "abc<#111111,Roboto,18> ..." — each tag follows the text it styles.
String toColorTxt(List<Run> runs) {
  final b = StringBuffer();
  for (final r in runs) {
    final parts = r.t.split('\n');
    for (int k = 0; k < parts.length; k++) {
      if (parts[k].isNotEmpty) {
        b.write('${parts[k]}<#${r.s.hex},${r.s.font},${r.s.size.round()}${r.s.bold ? ',b' : ''}>');
      }
      if (k < parts.length - 1) b.write('\n');
    }
  }
  return b.toString();
}

/// Reads the format above. Accepts '#' or '$' before the hex code.
List<Run> fromColorTxt(String src) {
  final re = RegExp(
      r'<[#$]([0-9a-fA-F]{6})(?:\s*,\s*([^,>]+))?(?:\s*,\s*(\d+))?(?:\s*,\s*(b))?\s*>');
  final runs = <Run>[];
  int last = 0;
  for (final m in re.allMatches(src)) {
    final seg = src.substring(last, m.start);
    if (seg.isNotEmpty) {
      runs.add(Run(
          seg,
          TS(0xFF000000 | int.parse(m[1]!, radix: 16), (m[2] ?? 'Roboto').trim(),
              double.tryParse(m[3] ?? '') ?? 18, m[4] != null)));
    }
    last = m.end;
  }
  if (last < src.length) runs.add(Run(src.substring(last), TS.def));
  return runs;
}

String _x(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Minimal .docx (a zip with 3 XML files) keeping color, font, size, bold.
List<int> toDocx(Note n) {
  final body = StringBuffer(
      '<w:p><w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t>${_x(n.title)}</w:t></w:r></w:p><w:p>');
  for (final r in n.runs) {
    final parts = r.t.split('\n');
    for (int k = 0; k < parts.length; k++) {
      if (parts[k].isNotEmpty) {
        body.write('<w:r><w:rPr><w:rFonts w:ascii="${_x(r.s.font)}" w:hAnsi="${_x(r.s.font)}"/>'
            '${r.s.bold ? '<w:b/>' : ''}<w:color w:val="${r.s.hex}"/>'
            '<w:sz w:val="${(r.s.size * 2).round()}"/></w:rPr>'
            '<w:t xml:space="preserve">${_x(parts[k])}</w:t></w:r>');
      }
      if (k < parts.length - 1) body.write('</w:p><w:p>');
    }
  }
  body.write('</w:p>');

  const ns = 'http://schemas.openxmlformats.org/';
  final files = {
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="${ns}package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="${ns}package/2006/relationships"><Relationship Id="rId1" Type="${ns}officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="${ns}wordprocessingml/2006/main"><w:body>$body</w:body></w:document>',
  };
  final ar = Archive();
  files.forEach((k, v) {
    final d = utf8.encode(v);
    ar.addFile(ArchiveFile(k, d.length, d));
  });
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
