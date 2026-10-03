import 'package:flutter/material.dart';
import 'pages/notes_page.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  purgeOldTrash(); // trash older than 30 days is removed
  runApp(MaterialApp(
    title: 'ColorNote',
    theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
    home: const NotesPage(),
  ));
}
