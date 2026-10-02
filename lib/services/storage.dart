import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

late SharedPreferences _prefs;

Future<void> initStorage() async => _prefs = await SharedPreferences.getInstance();

// ---- Notes ----

List<Note> loadNotes() => (_prefs.getStringList('notes') ?? [])
    .map((s) => Note.fromJson(jsonDecode(s)))
    .toList();

void _writeNotes(List<Note> all) =>
    _prefs.setStringList('notes', all.map((x) => jsonEncode(x.toJson())).toList());

void saveNote(Note n) {
  final all = loadNotes();
  final i = all.indexWhere((x) => x.id == n.id);
  i >= 0 ? all[i] = n : all.insert(0, n);
  _writeNotes(all);
}

void deleteNote(String id) => _writeNotes(loadNotes()..removeWhere((x) => x.id == id));

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
