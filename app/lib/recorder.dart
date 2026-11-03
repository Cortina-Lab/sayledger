import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'theme.dart';
import 'widgets.dart';

/// Press and hold to record (16 kHz mono WAV, what Muse Voice Transcribe
/// accepts); release to hand the audio over.
class HoldToSpeak extends StatefulWidget {
  const HoldToSpeak({super.key, required this.onAudio, this.size = 116});
  final Future<void> Function(Uint8List wav) onAudio;
  final double size;

  @override
  State<HoldToSpeak> createState() => _HoldToSpeakState();
}

class _HoldToSpeakState extends State<HoldToSpeak> with SingleTickerProviderStateMixin {
  final _rec = AudioRecorder();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..stop();
  StreamSubscription<Amplitude>? _ampSub;
  bool _recording = false;
  bool _busy = false;
  double _level = 0;
  DateTime? _started;

  @override
  void dispose() {
    _ampSub?.cancel();
    _pulse.dispose();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    if (!await _rec.hasPermission()) {
      if (mounted) showSnack(context, 'Allow microphone access to speak entries.');
      return;
    }
    final dir = await getTemporaryDirectory();
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: '${dir.path}/sayledger_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    HapticFeedback.mediumImpact();
    _started = DateTime.now();
    _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      // dBFS (-60..0) -> 0..1
      if (mounted) setState(() => _level = ((a.current + 60) / 60).clamp(0.0, 1.0));
    });
    _pulse.repeat(reverse: true);
    setState(() => _recording = true);
  }

  Future<void> _stop() async {
    if (!_recording) return;
    final path = await _rec.stop();
    await _ampSub?.cancel();
    _pulse.stop();
    final heldMs = DateTime.now().difference(_started ?? DateTime.now()).inMilliseconds;
    setState(() => (_recording = false, _level = 0));
    if (path == null) return;
    final file = File(path);
    if (heldMs < 700) {
      file.delete().ignore();
      if (mounted) showSnack(context, 'Keep holding while you speak, then let go.');
      return;
    }
    HapticFeedback.lightImpact();
    final bytes = await file.readAsBytes();
    file.delete().ignore();
    setState(() => _busy = true);
    try {
      await widget.onAudio(bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.size;
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final ring = _recording ? 1.0 + 0.18 * _pulse.value + 0.35 * _level : 1.0;
          return SizedBox(
            width: s * 1.7,
            height: s * 1.7,
            child: Stack(alignment: Alignment.center, children: [
              if (_recording)
                Transform.scale(
                  scale: ring,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withValues(alpha: 0.18)),
                  ),
                ),
              AnimatedScale(
                scale: _recording ? 1.06 : 1,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent,
                    boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.3), blurRadius: 36, spreadRadius: 3, offset: const Offset(0, 10))],
                  ),
                  child: _busy
                      ? const Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
                      : Icon(_recording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded, color: Colors.white, size: s * 0.38),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
