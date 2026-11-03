import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

/// First run: name the shop, pick the region, get a private book.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.another = false, this.region});

  /// Opened from the book switcher / Settings to add a second shop.
  final bool another;
  final String? region;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  late final _currency = TextEditingController(text: _regions[widget.region ?? 'IN']!.$2);
  late String _region = widget.region ?? 'IN';
  bool _busy = false;

  static const _regions = {'IN': ('India', 'INR'), 'US': ('USA', 'USD'), 'XX': ('Other', '')};

  Future<void> _start({bool restore = false}) async {
    final name = _name.text.trim().isEmpty ? 'My Shop' : _name.text.trim();
    final cur = _currency.text.trim().toUpperCase();
    if (cur.length != 3) return showSnack(context, 'Enter a 3-letter currency code, e.g. EUR.');
    Uint8List? backup;
    if (restore) {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      backup = await picked.readAsBytes();
    }
    setState(() => _busy = true);
    try {
      await Api.instance.createBook(name, cur);
      if (backup != null) await Api.instance.restore(backup);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _server() async {
    final c = TextEditingController(text: Api.instance.base);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'http://192.168.1.3:8077')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    await Api.instance.setBase(url);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: widget.another ? innerBar('New book') : null,
      body: SafeArea(
        child: ListView(padding: EdgeInsets.fromLTRB(24, widget.another ? 8 : 40, 24, 24), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 34),
          )),
          const SizedBox(height: 22),
          Text(widget.another ? 'Another shop' : 'SayLedger', style: display(context, 40)),
          const SizedBox(height: 6),
          Text("Say it. It's in the book.", style: display(context, 20, color: c.accent, weight: FontWeight.w500)),
          const SizedBox(height: 14),
          Text(
            'Speak or type your shop\'s credit, payments and sales in any language. '
            'You check every entry before it is saved, and every total is calculated from your book.',
            style: TextStyle(fontSize: 15.5, color: c.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 28),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Shop name')),
          const SizedBox(height: 20),
          const Eyebrow('Region'),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [for (final e in _regions.entries) ButtonSegment(value: e.key, label: Text(e.value.$1))],
            selected: {_region},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() {
              _region = v.first;
              final cur = _regions[_region]!.$2;
              _currency.text = cur.isEmpty ? '' : cur;
            }),
          ),
          if (_region == 'XX') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _currency,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              decoration: const InputDecoration(labelText: 'Currency code (e.g. EUR, GBP, NGN, IDR)'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _start, child: Text(widget.another ? 'Create book' : 'Open my book')),
          const SizedBox(height: 6),
          TextButton(onPressed: _busy ? null : () => _start(restore: true), child: const Text('Restore from a backup')),
          Center(
            child: TextButton.icon(
              onPressed: _busy ? null : _server,
              icon: const Icon(Icons.dns_outlined, size: 16),
              label: Text('Server: ${Api.instance.base}', style: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your book is private to this device. No login, no ads. You can back it up or erase it any time in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkFaint, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}
