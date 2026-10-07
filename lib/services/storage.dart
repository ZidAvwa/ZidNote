import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/note.dart';

late SharedPreferences _prefs;
late Database _db;
late String imagesDir;

/// Every note (including trash) by id. Reads are served from here (instant);
/// every change is also written to the SQLite database.
final Map<String, Note> _notes = {};

const trashDays = 30;
int _now() => DateTime.now().millisecondsSinceEpoch;

void _bg(Future<dynamic> f) => f.catchError((Object e) {
      debugPrint('storage: $e');
      return null;
    });

Future<void> initStorage() async {
  _prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  imagesDir = '${docs.path}/images';
  Directory(imagesDir).createSync(recursive: true);

  _db = await openDatabase(
    '${await getDatabasesPath()}/colornote.db',
    version: 1,
    onCreate: (db, v) => db.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, json TEXT NOT NULL)'),
  );
  for (final r in await _db.query('notes')) {
    final n = Note.fromJson(jsonDecode(r['json'] as String));
    _notes[n.id] = n;
  }

  // One-time move of notes saved by older versions (SharedPreferences) into the database.
  final old = _prefs.getStringList('notes');
  if (old != null) {
    final batch = _db.batch();
    for (final s in old) {
      final n = Note.fromJson(jsonDecode(s));
      if (_notes.containsKey(n.id)) continue;
      _notes[n.id] = n;
      batch.insert('notes', {'id': n.id, 'json': s}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _prefs.remove('notes');
  }
}

// ---- Notes (active + trash share one table; trash = deletedAt != 0) ----

List<Note> loadNotes() => _notes.values.where((n) => n.deletedAt == 0).toList();
List<Note> loadTrash() => _notes.values.where((n) => n.deletedAt != 0).toList();
bool noteExists(String id) => _notes.containsKey(id);

/// Inserts or replaces notes by id, in one write.
void saveMany(List<Note> ns) {
  if (ns.isEmpty) return;
  final batch = _db.batch();
  for (final n in ns) {
    _notes[n.id] = n;
    batch.insert('notes', {'id': n.id, 'json': jsonEncode(n.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  _bg(batch.commit(noResult: true));
}

void saveNote(Note n) => saveMany([n]);

void trashNote(String id) {
  final n = _notes[id];
  if (n == null) return;
  n.deletedAt = _now();
  n.pinned = false;
  saveMany([n]);
}

void restoreNote(String id) {
  final n = _notes[id];
  if (n == null) return;
  n.deletedAt = 0;
  saveMany([n]);
}

void _purge(List<String> ids) {
  if (ids.isEmpty) return;
  final batch = _db.batch();
  for (final id in ids) {
    _notes.remove(id);
    batch.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
  _bg(batch.commit(noResult: true));
}

void purgeNote(String id) => _purge([id]);

void emptyTrash() => _purge(loadTrash().map((n) => n.id).toList());

/// Permanently removes notes that have been in the trash longer than [trashDays].
void purgeOldTrash() {
  final cut = _now() - trashDays * 86400000;
  _purge(loadTrash().where((n) => n.deletedAt <= cut).map((n) => n.id).toList());
}

// ---- Groups (folders) ----

List<String> loadGroups() => _prefs.getStringList('groups') ?? [];
void saveGroups(List<String> g) => _prefs.setStringList('groups', g);

// ---- Color palette presets (persist after the app is closed) ----

Map<String, List<int>> loadPresets() {
  final raw = _prefs.getString('presets');
  if (raw != null) {
    return (jsonDecode(raw) as Map)
        .map((k, v) => MapEntry(k as String, (v as List).cast<int>()));
  }
  final old = _prefs.getStringList('palette'); // from version 1.0
  return {
    'Basic': [
      0xFF000000, 0xFFF44336, 0xFF2196F3, 0xFF4CAF50,
      0xFFFF9800, 0xFF9C27B0, 0xFF795548, 0xFF9E9E9E,
    ],
    'Pastel': [
      0xFFFFADAD, 0xFFFFD6A5, 0xFFFDFFB6, 0xFFCAFFBF,
      0xFF9BF6FF, 0xFFA0C4FF, 0xFFBDB2FF, 0xFFFFC6FF,
    ],
    if (old != null) 'My colors': old.map(int.parse).toList(),
  };
}

void savePresets(Map<String, List<int>> p) => _prefs.setString('presets', jsonEncode(p));

String loadActivePreset() => _prefs.getString('activePreset') ?? 'Basic';
void saveActivePreset(String n) => _prefs.setString('activePreset', n);

// ---- Sort ----

String loadSort() => _prefs.getString('sort') ?? 'modified';
void saveSort(String s) => _prefs.setString('sort', s);

// ---- Group colors (the color-coded group button) ----

const groupPalette = [
  0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF43A047,
  0xFF00ACC1, 0xFF1E88E5, 0xFF8E24AA, 0xFFD81B60,
];

Map<String, int> loadGroupColors() {
  final raw = _prefs.getString('groupColors');
  final m = raw == null
      ? <String, int>{}
      : (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as int));
  final gs = loadGroups();
  var changed = false;
  for (int i = 0; i < gs.length; i++) {
    if (!m.containsKey(gs[i])) {
      m[gs[i]] = groupPalette[i % groupPalette.length];
      changed = true;
    }
  }
  if (changed) saveGroupColors(m);
  return m;
}

void saveGroupColors(Map<String, int> m) => _prefs.setString('groupColors', jsonEncode(m));

// ---- Misc ----


/// 'system', 'light' or 'dark'
String loadTheme() => _prefs.getString('theme') ?? 'system';
void saveTheme(String t) => _prefs.setString('theme', t);

// ---- Images (photos and drawings live as files; notes only keep the names) ----

String imagePath(String name) => '$imagesDir/$name';
String newImageName(String prefix, String ext) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext';
bool isDrawing(String name) => name.startsWith('draw_');
String strokesName(String drawing) => drawing.replaceAll(RegExp(r'\.png$'), '.json');

/// Deletes image files that no note (including the trash) uses any more.
Future<void> cleanupImages() async {
  final used = <String>{};
  for (final n in _notes.values) {
    for (final i in n.images) {
      used.add(i);
      if (isDrawing(i)) used.add(strokesName(i));
    }
  }
  await for (final f in Directory(imagesDir).list()) {
    if (f is File && !used.contains(f.uri.pathSegments.last)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
