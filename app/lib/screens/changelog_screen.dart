import 'package:flutter/material.dart';

import '../changelog.dart';

/// Historique des versions (Paramètres → Historique des versions).
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des versions')),
      body: ListView.builder(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        itemCount: kChangelog.length,
        itemBuilder: (context, i) {
          final r = kChangelog[i];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: i == 0
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r.version,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: i == 0 ? scheme.onPrimary : scheme.primary,
                        ),
                      ),
                    ),
                    if (i == 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        'actuelle',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                for (final note in r.notes)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 10),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(fontSize: 14, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (i < kChangelog.length - 1)
                  const Divider(height: 22),
              ],
            ),
          );
        },
      ),
    );
  }
}
