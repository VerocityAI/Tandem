import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tandem/core/api/api.dart';
import 'package:tandem/core/widgets/score_ring.dart';

class OutreachScreen extends ConsumerStatefulWidget {
  const OutreachScreen({required this.fromKey, required this.toKey, super.key});
  final String fromKey;
  final String toKey;

  @override
  ConsumerState<OutreachScreen> createState() => _OutreachScreenState();
}

class _OutreachScreenState extends ConsumerState<OutreachScreen> {
  final _angleController = TextEditingController();
  Map<String, dynamic>? _from;
  Map<String, dynamic>? _to;
  Map<String, dynamic>? _draft;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _angleController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('channels').doc(widget.fromKey).get(),
        db.collection('channels').doc(widget.toKey).get(),
      ]);
      _from = results[0].data();
      _to = results[1].data();
      if (mounted) setState(() => _loading = false);
      await _generate();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final angle = _angleController.text.trim();
      final result = await ref.read(apiProvider).draftOutreach(
            fromKey: widget.fromKey,
            toKey: widget.toKey,
            angle: angle.isEmpty ? null : angle,
          );
      if (mounted) setState(() => _draft = result);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _copy(String label, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draft outreach')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _pairHeader(context),
                const SizedBox(height: 16),
                TextField(
                  controller: _angleController,
                  decoration: const InputDecoration(
                    labelText: 'Collaboration angle (optional)',
                    hintText: 'e.g. a Shorts swap on city travel tips',
                    prefixIcon: Icon(Icons.tips_and_updates_outlined),
                  ),
                  onSubmitted: (_) => _generate(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_generating
                      ? 'Writing…'
                      : _draft == null
                          ? 'Generate message'
                          : 'Regenerate'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                if (_draft != null) ...[
                  const SizedBox(height: 20),
                  _draftView(context, _draft!),
                ],
              ],
            ),
    );
  }

  Widget _pairHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _channelChip(_from, 'You')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child:
                  Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
            ),
            Expanded(child: _channelChip(_to, 'Them')),
          ],
        ),
      ),
    );
  }

  Widget _channelChip(Map<String, dynamic>? data, String fallback) {
    final name = data?['name'] as String? ?? fallback;
    final niche = data?['niche'] as String? ?? '';
    final platform =
        (data?['ref'] as Map<String, dynamic>?)?['platform'] as String?;
    return Column(
      children: [
        ChannelAvatar(
          name: name,
          niche: niche,
          imageUrl: data?['thumbnailUrl'] as String?,
          platform: platform,
          size: 52,
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _draftView(BuildContext context, Map<String, dynamic> draft) {
    final theme = Theme.of(context);
    final subject = draft['subject'] as String? ?? '';
    final message = draft['message'] as String? ?? '';
    final talkingPoints =
        (draft['talkingPoints'] as List<dynamic>?)?.cast<String>() ?? [];
    final cta = draft['callToAction'] as String?;
    final full = [
      if (subject.isNotEmpty) 'Subject: $subject',
      message,
      if (cta != null && cta.isNotEmpty) cta,
    ].join('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subject.isNotEmpty) ...[
          _fieldLabel(context, 'Subject', () => _copy('Subject', subject)),
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(subject,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _fieldLabel(context, 'Message', () => _copy('Message', message)),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
        ),
        if (talkingPoints.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Talking points', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          ...talkingPoints.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p)),
                ],
              ),
            ),
          ),
        ],
        if (cta != null && cta.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(cta)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _copy('Full message', full),
          icon: const Icon(Icons.copy_all),
          label: const Text('Copy full message'),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String label, VoidCallback onCopy) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        TextButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy, size: 15),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}
