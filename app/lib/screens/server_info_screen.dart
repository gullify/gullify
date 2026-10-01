import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_info_repository.dart';
import '../api/update_repository.dart';
import '../state/admin.dart';
import '../state/auth.dart';
import '../state/server_info.dart';
import '../state/server_update.dart';
import 'settings_screen.dart' show formatBytes;

/// Infos du serveur : espace disque restant, poids de la musique et des
/// données, taille de la bibliothèque et de la base, versions.
/// Accessible depuis Paramètres → Compte.
class ServerInfoScreen extends ConsumerWidget {
  const ServerInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(serverInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Infos du serveur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            // Les deux : « actualiser » sans rafraîchir la carte de mise à
            // jour laissait le seul moyen de la réveiller hors de portée.
            onPressed: () {
              ref.invalidate(serverInfoProvider);
              ref.invalidate(serverUpdateProvider);
            },
          ),
        ],
      ),
      body: info.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(serverInfoProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(serverInfoProvider);
            ref.invalidate(serverUpdateProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AddressCard(url: ref.watch(authProvider).serverUrl ?? ''),
              const SizedBox(height: 16),
              if (ref.watch(isAdminProvider)) ...[
                const _UpdateCard(),
                const SizedBox(height: 16),
              ],
              for (final disk in data.disks) ...[
                _DiskCard(disk: disk),
                const SizedBox(height: 16),
              ],
              _StorageCard(music: data.music, data: data.data),
              const SizedBox(height: 16),
              _LibraryCard(
                library: data.library,
                databaseBytes: data.databaseBytes,
              ),
              const SizedBox(height: 16),
              _SystemCard(system: data.system),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Infos indisponibles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de base : un titre avec son icône, puis le contenu.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Une ligne « libellé … valeur ».
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      icon: Icons.dns_outlined,
      title: 'Adresse',
      children: [
        Text(
          url,
          style: TextStyle(
            fontSize: 13.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Espace disque : la jauge et, en gros, ce qu'il reste.
class _DiskCard extends StatelessWidget {
  const _DiskCard({required this.disk});

  final ServerDisk disk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = disk.usedRatio;
    final tight = ratio >= 0.9;
    final color = tight
        ? scheme.error
        : ratio >= 0.75
            ? Colors.orange
            : scheme.primary;

    return _InfoCard(
      icon: Icons.storage_outlined,
      title: 'Espace disque · ${disk.label}',
      children: [
        Text(
          '${formatBytes(disk.free)} libres',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        _InfoRow(
          'Utilisé',
          '${formatBytes(disk.used)} sur ${formatBytes(disk.total)}'
              ' (${(ratio * 100).round()} %)',
        ),
        if (tight)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Le disque est presque plein.',
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
          ),
      ],
    );
  }
}

/// Poids des dossiers du serveur (musique, données).
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.music, required this.data});

  final ServerFolderSize music;
  final ServerFolderSize data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final at = music.computedAt ?? data.computedAt;

    return _InfoCard(
      icon: Icons.folder_outlined,
      title: 'Occupation',
      children: [
        _InfoRow(
          'Musique',
          music.bytes == null ? '—' : formatBytes(music.bytes!),
        ),
        _InfoRow(
          'Données (cache, journaux…)',
          data.bytes == null ? '—' : formatBytes(data.bytes!),
        ),
        if (at != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Mesuré ${_ago(at)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.library, required this.databaseBytes});

  final ServerLibraryInfo library;
  final int databaseBytes;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      icon: Icons.library_music_outlined,
      title: 'Bibliothèque',
      children: [
        _InfoRow('Titres', _count(library.songs)),
        _InfoRow('Albums', _count(library.albums)),
        _InfoRow('Artistes', _count(library.artists)),
        _InfoRow('Genres', _count(library.genres)),
        if (library.playlists > 0)
          _InfoRow('Playlists', _count(library.playlists)),
        _InfoRow('Durée totale', _longDuration(library.duration)),
        _InfoRow('Comptes', _count(library.users)),
        _InfoRow('Base de données', formatBytes(databaseBytes)),
        _InfoRow(
          'Dernier scan',
          library.lastScan == null ? 'jamais' : _ago(library.lastScan!),
        ),
      ],
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.system});

  final ServerSystemInfo system;

  @override
  Widget build(BuildContext context) {
    final memTotal = system.memTotal;
    final memFree = system.memFree;

    return _InfoCard(
      icon: Icons.memory,
      title: 'Système',
      children: [
        if (system.os.isNotEmpty) _InfoRow('Système', system.os),
        if (system.server.isNotEmpty) _InfoRow('Serveur web', system.server),
        if (system.php.isNotEmpty) _InfoRow('PHP', system.php),
        if (system.kernel.isNotEmpty) _InfoRow('Noyau', system.kernel),
        if (system.cpus != null) _InfoRow('Processeurs', '${system.cpus}'),
        if (system.load.isNotEmpty)
          _InfoRow(
            'Charge (1/5/15 min)',
            system.load.map((v) => v.toStringAsFixed(2)).join(' · '),
          ),
        if (memTotal != null && memFree != null)
          _InfoRow(
            'Mémoire libre',
            '${formatBytes(memFree)} sur ${formatBytes(memTotal)}',
          ),
        if (system.uptime != null)
          _InfoRow('En marche depuis', _uptime(system.uptime!)),
        if (system.time.isNotEmpty)
          _InfoRow(
            'Heure du serveur',
            '${system.time}'
                '${system.timezone.isEmpty ? '' : ' (${system.timezone})'}',
          ),
      ],
    );
  }
}

/// 22765 → « 22 765 » : milliers séparés par une espace fine insécable,
/// comme le veut la typographie française.
String _count(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u202f');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Durée cumulée de la bibliothèque : « 55 j 20 h » ou « 3 h 12 min ».
String _longDuration(int seconds) {
  if (seconds <= 0) return '—';
  final d = Duration(seconds: seconds);
  if (d.inDays >= 1) return '${d.inDays} j ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

String _uptime(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} j ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

String _ago(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 30) return 'il y a ${diff.inDays} j';
  final d = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'le ${two(d.day)}/${two(d.month)}/${d.year}';
}

/// La mise à jour du serveur, pour qui a le droit de la décider.
///
/// Trois états, et un seul bouton. « À jour » ne se dit que lorsqu'on le
/// sait : si le dépôt d'images n'a pas répondu, la carte ne promet rien
/// plutôt que de rassurer à tort.
///
/// Pendant l'opération, le serveur disparaît — c'est précisément ce qu'on
/// lui a demandé. On continue donc de l'appeler, et les erreurs de réseau
/// de ces quelques secondes ne sont pas des pannes : c'est son retour, avec
/// un nouveau numéro de version, qui marque la fin.
class _UpdateCard extends ConsumerStatefulWidget {
  const _UpdateCard();

  @override
  ConsumerState<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<_UpdateCard> {
  Timer? _rappel;
  bool _demandee = false;
  String? _erreur;

  @override
  void dispose() {
    _rappel?.cancel();
    super.dispose();
  }

  Future<void> _lancer(String action) async {
    setState(() {
      _demandee = true;
      _erreur = null;
    });
    try {
      await ref.read(updateRepositoryProvider).lancer(action: action);
      _surveille();
    } catch (e) {
      setState(() {
        _demandee = false;
        _erreur = '$e';
      });
    }
  }

  /// Redemander l'état jusqu'à ce que le serveur soit revenu.
  ///
  /// Il tombe au milieu de l'opération — c'est ce qu'on lui a demandé — donc
  /// son silence pendant ces secondes-là est attendu. La fin, c'est son
  /// retour avec un journal qui dit « fini ».
  void _surveille() {
    _rappel?.cancel();
    _rappel = Timer.periodic(const Duration(seconds: 3), (minuteur) {
      if (!mounted) {
        minuteur.cancel();
        _rappel = null;
        return;
      }
      final etat = ref.read(serverUpdateProvider).asData?.value;
      // Un serveur qui répond et ne travaille plus : c'est fini. Un serveur
      // muet ne conclut rien — il est en train de revenir.
      if (_demandee && etat != null && etat.joignable && !etat.enCours) {
        minuteur.cancel();
        _rappel = null;
        setState(() => _demandee = false);
        ref.invalidate(serverInfoProvider);
        return;
      }
      ref.invalidate(serverUpdateProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final etat = ref.watch(serverUpdateProvider);

    // Le minuteur est rétabli à chaque construction tant qu'on attend : s'il
    // disparaissait — l'écran reconstruit, l'état recréé — la carte resterait
    // figée sur la dernière réponse reçue, sans rien pour la réveiller.
    if (_demandee && _rappel == null) _surveille();

    return _InfoCard(
      icon: Icons.system_update_alt,
      title: 'Mise à jour',
      children: [
        ...etat.when(
          loading: () => const [_LigneDiscrete('Je regarde…')],
          // Le provider ne tombe plus en panne quand le serveur se tait (voir
          // serverUpdateProvider) ; ceci ne couvre donc qu'un imprévu.
          error: (e, _) => [_LigneDiscrete('État inconnu : $e')],
          data: (maj) => _contenu(context, maj),
        ),
        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!, style: TextStyle(fontSize: 13, color: scheme.error)),
        ],
      ],
    );
  }

  List<Widget> _contenu(BuildContext context, ServerUpdate maj) {
    final scheme = Theme.of(context).colorScheme;
    final enCours = _demandee || maj.enCours;

    // Muet : il redémarre, ou il n'est plus là. Pendant qu'on attend, c'est
    // attendu ; en dehors, c'est à dire.
    if (!maj.joignable) {
      return [
        const SizedBox(height: 4),
        const LinearProgressIndicator(),
        const SizedBox(height: 10),
        _LigneDiscrete(enCours
            ? 'Le serveur redémarre…'
            : 'Le serveur ne répond pas.'),
      ];
    }

    final lignes = <Widget>[
      _LigneDiscrete(maj.installee == null
          ? 'Version : construite sur place'
          : 'Version installée : ${maj.installee}'),
    ];

    if (enCours) {
      lignes.addAll([
        const SizedBox(height: 10),
        const LinearProgressIndicator(),
        const SizedBox(height: 10),
        for (final ligne in maj.journal.where((l) => l != 'fini').take(6))
          _LigneDiscrete(ligne),
        if (maj.journal.isEmpty) const _LigneDiscrete('En cours…'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              ref.invalidate(serverUpdateProvider);
              _surveille();
            },
            child: const Text('Vérifier maintenant'),
          ),
        ),
      ]);
      return lignes;
    }

    if (!maj.possible) {
      // Pas de bouton : un conteneur ne se remplace pas lui-même. On dit donc
      // le geste à faire sur la machine — et il n'est pas le même selon que
      // le serveur porte le code ou qu'il tire une image déjà construite.
      lignes.addAll([
        if (maj.disponible != null && maj.aJour == false)
          _LigneDiscrete('Version disponible : ${maj.disponible}'),
        const SizedBox(height: 6),
        _LigneDiscrete(
          maj.installee == null
              ? 'Ce serveur porte le code : il se met à jour avec ./update.sh '
                'sur sa machine.'
              : 'Pour le mettre à jour, dans son dossier Gullify sur la '
                'machine : docker compose pull puis docker compose up -d.',
        ),
      ]);
      return lignes;
    }

    // Le compagnon est là : les deux gestes sont offerts.
    //
    // Mettre à jour reste proposé même quand on se croit à jour : un serveur
    // qui porte le code n'a pas de version publiée à laquelle se comparer, et
    // « à jour » s'y dirait sans rien en savoir.
    if (maj.aJour == true) {
      lignes.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('À jour', style: TextStyle(fontSize: 13.5)),
          ],
        ),
      ));
    } else if (maj.aJour == false) {
      lignes.add(_LigneDiscrete('Version disponible : ${maj.disponible}'));
    } else {
      lignes.add(const _LigneDiscrete(
        "Le dépôt des versions n'a pas répondu : je ne sais pas s'il en existe "
        'une plus récente.',
      ));
    }

    lignes.addAll([
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _confirmer(
                context,
                'Redémarrer le serveur ?',
                'Il sera injoignable une minute environ, et la lecture en '
                    'cours s\'arrêtera.',
                'Redémarrer',
                'redemarrer',
              ),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Redémarrer'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _confirmer(
                context,
                'Mettre à jour le serveur ?',
                maj.aJour == false
                    ? 'La version ${maj.disponible} sera installée. Quelques '
                        'minutes, pendant lesquelles le serveur est injoignable.'
                    : 'La dernière version sera installée. Quelques minutes, '
                        'pendant lesquelles le serveur est injoignable.',
                'Mettre à jour',
                'maj',
              ),
              icon: const Icon(Icons.download),
              label: const Text('Mettre à jour'),
            ),
          ),
        ],
      ),
    ]);
    return lignes;
  }

  /// Rien ne part sans un second geste : les deux boutons coupent la musique
  /// de tout le monde, et celui du bas peut changer la version du serveur.
  Future<void> _confirmer(
    BuildContext context,
    String titre,
    String corps,
    String bouton,
    String action,
  ) async {
    final oui = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Text(corps),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(bouton),
          ),
        ],
      ),
    );
    if (oui == true) await _lancer(action);
  }
}

class _LigneDiscrete extends StatelessWidget {
  const _LigneDiscrete(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      texte,
      style: TextStyle(
        fontSize: 13.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
