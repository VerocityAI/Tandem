import 'package:flutter/material.dart';

class OutreachScreen extends StatelessWidget {
  const OutreachScreen({required this.fromKey, required this.toKey, super.key});
  final String fromKey;
  final String toKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Outreach draft')),
    body: Center(child: Text('From $fromKey → $toKey')),
  );
}
