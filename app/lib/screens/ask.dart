import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../recorder.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ask the book a question by voice or text. The model only picks what is
/// being asked; every number shown is calculated from saved entries.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _q = TextEditingController();
  final List<Map<String, dynamic>> _thread = [];
  bool _busy = false;

  static const _examples = ['How much do customers owe me?', 'Who owes the most?', "Today's summary", 'This week'];

  Future<void> _run(Future<Map<String, dynamic>> Function() call) async {
    setState(() => _busy = true);
    try {
      final r = await call();
      if (mounted) setState(() => _thread.insert(0, r));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _askText([String? text]) {
    final q = (text ?? _q.text).trim();
    if (q.isEmpty) return;
    _q.clear();
    FocusScope.of(context).unfocus();
    _run(() => Api.instance.askText(q));
  }

  Future<void> _askVoice(Uint8List wav) => _run(() => Api.instance.askVoice(wav));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: innerBar('Ask your book'),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        Text('Answers are calculated from your saved entries.', style: TextStyle(color: c.inkSoft)),
        const SizedBox(height: 8),
        Center(child: HoldToSpeak(onAudio: _askVoice, size: 92)),
        Center(child: Text('Hold to ask', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink, fontSize: 16))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _askText(),
              decoration: const InputDecoration(hintText: 'Or type, e.g. "How much does Ramesh owe?"'),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 54,
            child: FilledButton(onPressed: _busy ? null : _askText, child: const Icon(Icons.arrow_upward_rounded)),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final ex in _examples)
            ActionChip(
              label: Text(ex),
              onPressed: _busy ? null : () => _askText(ex),
              backgroundColor: c.card,
              side: BorderSide(color: c.line),
              shape: const StadiumBorder(),
            ),
        ]),
        const SizedBox(height: 18),
        if (_busy) const Padding(padding: EdgeInsets.all(24), child: Working('Checking your book…')),
        for (final r in _thread) ...[_answer(r), const SizedBox(height: 12)],
      ]),
    );
  }

  Widget _answer(Map<String, dynamic> r) {
    final c = context.c;
    final cur = r['currency'] as String;
    final numbers = Map<String, dynamic>.from(r['numbers'] as Map);
    final refused = r['intent'] == 'none' || r['intent'] == 'unknown_party';
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('You asked'),
        const SizedBox(height: 4),
        Text(r['heard'] as String, style: display(context, 18, weight: FontWeight.w500)),
        const SizedBox(height: 12),
        Text(r['answer'] as String, style: TextStyle(fontSize: 17, height: 1.35, color: refused ? c.inkSoft : c.ink)),
        if (numbers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.calculate_outlined, size: 16, color: c.accent),
                const SizedBox(width: 6),
                const Eyebrow('Calculated from your book'),
              ]),
              const SizedBox(height: 8),
              for (final n in numbers.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(n.key, style: TextStyle(color: c.inkSoft))),
                    Text(
                      n.key == 'Entries' || n.key == 'Customers owing' ? '${n.value}' : formatMoney(n.value as int, cur),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}
