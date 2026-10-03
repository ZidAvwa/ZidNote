import 'dart:convert';
import '../models/note.dart';
import 'storage.dart';

/// One JSON file with all notes, groups, group colors and palette presets.
String makeBackup() => jsonEncode({
      'app': 'colornote',
      'version': 1,
      'notes': loadNotes().map((n) => n.toJson()).toList(),
      'groups': loadGroups(),
      'groupColors': loadGroupColors(),
      'presets': loadPresets(),
    });

/// Merges a backup into the app (nothing is deleted):
/// notes are added, or replaced when the backup copy is newer; missing groups
/// and palette presets are added. Returns how many notes were added/updated.
int restoreBackup(String src) {
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
