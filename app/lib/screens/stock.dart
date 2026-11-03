import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Photo of a shelf + an item name -> SAM 3.1 finds each one, the server
/// counts them and draws numbered boxes so the shopkeeper can check.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _item = TextEditingController();
  Uint8List? _photo;
  String _mime = 'image/jpeg';
  Map<String, dynamic>? _result;
  bool _busy = false;

  static const _examples = ['bottle', 'soap', 'packet', 'can', 'box'];

  Future<void> _pick(ImageSource source) async {
    final shot = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    setState(() {
      _photo = bytes;
      _mime = shot.mimeType ?? (shot.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      _result = null;
    });
  }

  Future<void> _count() async {
    final item = _item.text.trim();
    if (item.isEmpty) return showSnack(context, 'Type what to count, e.g. "bottle".');
    if (_photo == null) return showSnack(context, 'Take or choose a photo first.');
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final r = await Api.instance.stockCount(_photo!, _mime, item);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _result;
    return Scaffold(
      appBar: innerBar('Count stock'),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        Text('Photograph a shelf and say what to count.', style: TextStyle(color: c.inkSoft)),
        const SizedBox(height: 14),
        TextField(
          controller: _item,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Item to count', hintText: 'e.g. water bottle'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final ex in _examples)
            ActionChip(
              label: Text(ex),
              onPressed: () => setState(() => _item.text = ex),
              backgroundColor: c.card,
              side: BorderSide(color: c.line),
              shape: const StadiumBorder(),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (r != null) ...[
          Panel(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${r['count']}', style: display(context, 56, color: c.accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${r['item']}${r['count'] == 1 ? '' : 's'} found', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              TagChip('Approximate', bg: c.doubtSoft, fg: c.doubt),
            ]),
          ),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(base64Decode(r['overlay_jpeg'] as String))),
          const SizedBox(height: 8),
          Text(r['note'] as String, style: TextStyle(color: c.inkFaint)),
        ] else if (_photo != null)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(_photo!)),
        if (_busy) const Padding(padding: EdgeInsets.all(24), child: Working('Counting…')),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _count,
            icon: const Icon(Icons.filter_center_focus_rounded),
            label: Text(r == null ? 'Count' : 'Count again'),
          ),
        ),
      ),
    );
  }
}
