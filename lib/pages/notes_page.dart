import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/storage.dart';
import 'editor_page.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> notes = loadNotes();

  Future<void> open(Note n) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(note: n)));
    setState(() => notes = loadNotes());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Notes')),
        floatingActionButton: FloatingActionButton(
            onPressed: () =>
                open(Note(DateTime.now().millisecondsSinceEpoch.toString(), '', [])),
            child: const Icon(Icons.edit)),
        body: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(8),
          children: [
            for (final n in notes)
              Card(
                child: InkWell(
                  onTap: () => open(n),
                  onLongPress: () {
                    deleteNote(n.id);
                    setState(() => notes = loadNotes());
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title.isEmpty ? 'Untitled' : n.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Expanded(
                          child: Text.rich(
                              TextSpan(children: [
                                for (final r in n.runs) TextSpan(text: r.t, style: r.s.style)
                              ]),
                              overflow: TextOverflow.fade)),
                    ]),
                  ),
                ),
              )
          ],
        ),
      );
}
