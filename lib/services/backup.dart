import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import '../models/note.dart';
import 'storage.dart';

/// A .zip with backup.json (notes, groups, group colors, palette presets)
/// and the photos / drawings the notes use.
Future<List<int>> makeBackup() async {
  final notes = loadNotes();
  final json = utf8.encode(jsonEncode({
    'app': 'colornote',
    'version': 2,
    'notes': notes.map((n) => n.toJson()).toList(),
    'groups': loadGroups(),
    'groupColors': loadGroupColors(),
    'presets': loadPresets(),
  }));
  final ar = Archive()..addFile(ArchiveFile('backup.json', json.length, json));

  final used = <String>{};
  for (final n in notes) {
    for (final i in n.images) {
      used.add(i);
      if (isDrawing(i)) used.add(strokesName(i));
    }
  }
  for (final name in used) {
    final f = File(imagePath(name));
    if (await f.exists()) {
      final b = await f.readAsBytes();
      ar.addFile(ArchiveFile('images/$name', b.length, b));
    }
  }
  return ZipEncoder().encode(ar)!;
}

/// Merges a backup into the app (nothing is deleted). Accepts the new .zip and
/// the old plain .json backups. Returns how many notes were added/updated.
Future<int> restoreBackup(List<int> bytes) async {
  final String src;
  final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (isZip) {
    final ar = ZipDecoder().decodeBytes(bytes);
    final j = ar.findFile('backup.json');
    if (j == null) throw const FormatException('Not a ColorNote backup file');
    src = utf8.decode(j.content as List<int>);
    for (final f in ar) {
      if (!f.isFile || !f.name.startsWith('images/')) continue;
      final name = f.name.substring(7);
      if (name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) continue;
      await File(imagePath(name)).writeAsBytes(f.content as List<int>);
    }
  } else {
    src = utf8.decode(bytes);
  }
  return _merge(src);
}

int _merge(String src) {
  final j = jsonDecode(src);
  if (j is! Map || j['app'] != 'colornote') {
    throw const FormatException('Not a ColorNote backup file');
  }

  final local = {for (final n in loadNotes()) n.id: n};
  final incoming = <Note>[];
  for (final m in (j['notes'] as List? ?? [])) {
    final n = Note.fromJson(m as Map);
    final cur = local[n.id];
    if (cur == null || n.modified > cur.modified) incoming.add(n);
  }
  saveMany(incoming);

  final groups = loadGroups();
  final added = <String>[];
  for (final g in ((j['groups'] as List?) ?? []).cast<String>()) {
    if (!groups.contains(g)) {
      groups.add(g);
      added.add(g);
    }
  }
  saveGroups(groups);

  final colors = loadGroupColors();
  final backupColors = (j['groupColors'] as Map?) ?? {};
  for (final g in added) {
    final c = backupColors[g];
    if (c is int) colors[g] = c;
  }
  saveGroupColors(colors);

  final presets = loadPresets();
  ((j['presets'] as Map?) ?? {}).forEach((k, v) {
    if (!presets.containsKey(k)) presets[k as String] = (v as List).cast<int>();
  });
  savePresets(presets);

  return incoming.length;
}
