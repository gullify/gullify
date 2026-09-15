import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/admin_repository.dart';
import '../../state/admin.dart';
import '../../state/auth.dart';

/// La fiche d'un compte : mot de passe, dossier de musique, rôle, accès, et
/// le stockage (local ou SFTP). [user] nul = création.
///
/// Le serveur reste seul juge : il refuse qu'on se supprime, se suspende ou
/// se retire soi-même l'administration. L'écran cache simplement ces boutons
/// sur son propre compte, plutôt que de laisser appuyer pour rien.
class AdminUserScreen extends ConsumerStatefulWidget {
  const AdminUserScreen({super.key, this.user});

  final AdminUser? user;

  @override
  ConsumerState<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends ConsumerState<AdminUserScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.user?.username);
  late final _fullName = TextEditingController(text: widget.user?.fullName);
  final _password = TextEditingController();
  late final _directory = TextEditingController(
    text: widget.user?.musicDirectory,
  );
  late final _sftpHost = TextEditingController(text: widget.user?.sftpHost);
  late final _sftpPort = TextEditingController(
    text: '${widget.user?.sftpPort ?? 22}',
  );
  late final _sftpUser = TextEditingController(text: widget.user?.sftpUser);
  final _sftpPassword = TextEditingController();
  late final _sftpPath = TextEditingController(text: widget.user?.sftpPath);

  late bool _isAdmin = widget.user?.isAdmin ?? false;
  late bool _sftp = widget.user?.isSftp ?? false;
  bool _busy = false;

  bool get _creating => widget.user == null;

  @override
  void dispose() {
    for (final c in [
      _username,
      _fullName,
      _password,
      _directory,
      _sftpHost,
      _sftpPort,
      _sftpUser,
      _sftpPassword,
      _sftpPath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  /// Enveloppe commune : occupe l'écran, rapporte le message du serveur —
  /// c'est lui qui explique pourquoi un dossier est introuvable ou un mot de
  /// passe trop court — et rafraîchit la liste.
  Future<void> _run(
    Future<void> Function() action, {
    String? done,
    bool pop = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await action();
      ref.invalidate(adminUsersProvider);
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      if (pop && mounted) router.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () async {
        final id = await _repo.createUser(
          username: _username.text.trim(),
          password: _password.text,
          fullName: _fullName.text.trim(),
          isAdmin: _isAdmin,
          musicDirectory: _directory.text.trim(),
        );
        // Le stockage se règle en second : la création ne prend le SFTP en
        // compte que si on le lui donne d'emblée, et il lui faut de toute
        // façon l'identifiant du compte tout juste créé.
        if (_sftp && id > 0) {
          await _repo.updateStorage(
            userId: id,
            sftp: true,
            host: _sftpHost.text.trim(),
            port: int.tryParse(_sftpPort.text) ?? 22,
            user: _sftpUser.text.trim(),
            password: _sftpPassword.text,
            path: _sftpPath.text.trim(),
          );
        }
      },
      done: 'Compte créé',
      pop: true,
    );
  }

  Future<void> _confirmDelete(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${user.displayName} ?'),
        content: const Text(
          'Le compte et sa bibliothèque indexée disparaissent. Les fichiers '
          'de musique sur le disque, eux, ne sont pas touchés.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _repo.deleteUser(user.id),
      done: 'Compte supprimé',
      pop: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isSelf = ref.watch(authProvider).user?.id == user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? 'Nouveau compte' : user!.displayName),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (_busy) const LinearProgressIndicator(),
              _Section('Identité'),
              TextFormField(
                controller: _username,
                enabled: _creating,
                decoration: const InputDecoration(
                  labelText: 'Identifiant',
                  helperText: 'Lettres, chiffres, _ - . uniquement',
                ),
                validator: (v) {
                  if (!_creating) return null;
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Requis';
                  if (!RegExp(r'^[a-zA-Z0-9_\-.]+$').hasMatch(s)) {
                    return 'Caractère non autorisé';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                enabled: _creating,
                decoration: InputDecoration(
                  labelText: 'Nom complet',
                  // Le serveur n'expose pas de quoi le changer après coup.
                  helperText: _creating
                      ? null
                      : 'Se règle à la création seulement',
                ),
              ),

              _Section(_creating ? 'Mot de passe' : 'Changer le mot de passe'),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  helperText: _creating
                      ? 'Six caractères au moins'
                      : 'Laisse vide pour ne pas le changer',
                ),
                validator: (v) {
                  if (_creating && (v ?? '').length < 6) {
                    return 'Six caractères au moins';
                  }
                  return null;
                },
              ),
              if (!_creating) ...[
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _password.text.isEmpty
                      ? null
                      : () => _run(
                          () => _repo.updatePassword(user!.id, _password.text),
                          done: 'Mot de passe changé',
                        ),
                  child: const Text('Changer le mot de passe'),
                ),
              ],

              _Section('Bibliothèque'),
              _DirectoryField(controller: _directory),
              if (!_creating) ...[
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: () => _run(
                    () => _repo.updateDirectory(
                      user!.id,
                      _directory.text.trim(),
                    ),
                    done: 'Dossier enregistré',
                  ),
                  child: const Text('Enregistrer le dossier'),
                ),
              ],

              _Section('Stockage'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Local'),
                    icon: Icon(Icons.folder_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('SFTP'),
                    icon: Icon(Icons.dns_outlined),
                  ),
                ],
                selected: {_sftp},
                onSelectionChanged: (s) => setState(() => _sftp = s.first),
              ),
              if (_sftp) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _sftpHost,
                        decoration: const InputDecoration(labelText: 'Hôte'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sftpPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sftpUser,
                  decoration: const InputDecoration(
                    labelText: 'Utilisateur SFTP',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sftpPassword,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe SFTP',
                    // Le serveur ne renvoie jamais le mot de passe chiffré :
                    // on ne peut donc pas le réémettre, seulement le garder.
                    helperText: _creating
                        ? null
                        : 'Laisse vide pour garder celui enregistré',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sftpPath,
                  decoration: const InputDecoration(
                    labelText: 'Chemin distant',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        // Pris avant l'attente : après, le contexte peut ne
                        // plus être monté.
                        final messenger = ScaffoldMessenger.of(context);
                        _run(() async {
                          final msg = await _repo.testSftp(
                            host: _sftpHost.text.trim(),
                            port: int.tryParse(_sftpPort.text) ?? 22,
                            user: _sftpUser.text.trim(),
                            password: _sftpPassword.text,
                            path: _sftpPath.text.trim(),
                            userId: user?.id,
                          );
                          messenger.showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        });
                      },
                      icon: const Icon(Icons.network_check),
                      label: const Text('Tester la connexion'),
                    ),
                  ],
                ),
              ],
              if (!_creating) ...[
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: () => _run(
                    () => _repo.updateStorage(
                      userId: user!.id,
                      sftp: _sftp,
                      host: _sftpHost.text.trim(),
                      port: int.tryParse(_sftpPort.text) ?? 22,
                      user: _sftpUser.text.trim(),
                      password: _sftpPassword.text,
                      path: _sftpPath.text.trim(),
                    ),
                    done: 'Stockage enregistré',
                  ),
                  child: const Text('Enregistrer le stockage'),
                ),
              ],

              _Section('Rôle et accès'),
              if (_creating)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAdmin,
                  onChanged: (v) => setState(() => _isAdmin = v),
                  title: const Text('Administrateur'),
                  subtitle: const Text(
                    'Peut gérer les comptes et le stockage',
                  ),
                )
              else if (isSelf)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('C\'est votre compte'),
                  subtitle: Text(
                    'On ne peut ni changer son propre rôle, ni se suspendre, '
                    'ni se supprimer.',
                  ),
                )
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: user!.isAdmin,
                  onChanged: (_) => _run(
                    () => _repo.toggleAdmin(user.id),
                    done: 'Rôle changé',
                    pop: true,
                  ),
                  title: const Text('Administrateur'),
                  subtitle: const Text(
                    'Peut gérer les comptes et le stockage',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: user.isActive,
                  onChanged: (_) => _run(
                    () => _repo.toggleActive(user.id),
                    done: user.isActive ? 'Compte suspendu' : 'Compte réactivé',
                    pop: true,
                  ),
                  title: const Text('Accès autorisé'),
                  subtitle: const Text(
                    'Un compte suspendu ne peut plus se connecter',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(user),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer le compte'),
                ),
              ],

              if (_creating) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _create,
                  child: const Text('Créer le compte'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Le dossier de musique, choisi dans ce que le serveur propose — taper un
/// chemin à la main n'apporte rien et le serveur refuserait une faute.
class _DirectoryField extends ConsumerWidget {
  const _DirectoryField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirs = ref.watch(musicDirectoriesProvider);

    return dirs.when(
      loading: () => const TextField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Dossier de musique',
          helperText: 'Lecture des dossiers…',
        ),
      ),
      // Le serveur n'a pas pu lister : on retombe sur la saisie libre plutôt
      // que d'empêcher de régler quoi que ce soit.
      error: (e, _) => TextFormField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Dossier de musique',
          helperText: 'Dossiers illisibles — saisis le nom à la main',
        ),
      ),
      data: (info) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: info.directories.contains(controller.text)
                ? controller.text
                : null,
            decoration: InputDecoration(
              labelText: 'Dossier de musique',
              helperText: 'Sous ${info.basePath}',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Aucun')),
              for (final d in info.directories)
                DropdownMenuItem(value: d, child: Text(d)),
            ],
            onChanged: (v) => controller.text = v ?? '',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
