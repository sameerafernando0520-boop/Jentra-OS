import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../../shell/build_information_dialog.dart';
import '../../shell/notification_inbox.dart' show userInitials;
import 'account_photo.dart';

final accountPhotoStoreProvider = Provider<AccountPhotoStore>(
  (ref) => const SecureAccountPhotoStore(),
);
final accountPhotoPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => chooseAccountPhoto,
);
final accountPhotoOwnerProvider = Provider<AccountPhotoOwner?>((ref) {
  final actor = ref.watch(authenticatedActorProvider);
  final config = ref.watch(runtimeConfigProvider);
  if (actor.isLoading ||
      actor.hasError ||
      actor.value == null ||
      ref.watch(foundationGatewayProvider) == null ||
      !config.isSupabaseConfigured) {
    return null;
  }
  return (project: Uri.parse(config.supabaseUrl).origin, actor: actor.value!);
});
final accountPhotoProvider = FutureProvider.autoDispose<Uint8List?>((
  ref,
) async {
  final owner = ref.watch(accountPhotoOwnerProvider);
  if (owner == null) return null;
  return ref.watch(accountPhotoStoreProvider).read(owner);
});

Future<void> showAccountProfile(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AccountProfileDialog(),
);

class AccountProfileDialog extends ConsumerStatefulWidget {
  const AccountProfileDialog({super.key});

  @override
  ConsumerState<AccountProfileDialog> createState() =>
      _AccountProfileDialogState();
}

class _AccountProfileDialogState extends ConsumerState<AccountProfileDialog> {
  late final String? _actor;
  late final TextEditingController _name;
  final _form = GlobalKey<FormState>();
  bool _saving = false, _photoBusy = false;
  String? _error, _message;

  @override
  void initState() {
    super.initState();
    final user = ref.read(foundationGatewayProvider)?.currentUser;
    _actor = user?.id;
    final meta = user?.userMetadata ?? {};
    final name = meta['full_name'] ?? meta['name'];
    _name = TextEditingController(text: name is String ? name : '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _sameActor =>
      mounted &&
      _actor != null &&
      ref.read(foundationGatewayProvider)?.currentUser?.id == _actor;

  Future<void> _saveName() async {
    if (_saving ||
        _photoBusy ||
        !_sameActor ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(foundationGatewayProvider)!
          .updateAccountDisplayName(_name.text);
      if (_sameActor) setState(() => _message = 'Your name has been updated.');
    } on Object {
      if (_sameActor) {
        setState(
          () => _error = 'Your name could not be saved. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto({bool remove = false}) async {
    if (_photoBusy || _saving || !_sameActor) return;
    final owner = ref.read(accountPhotoOwnerProvider);
    if (owner == null) return;
    setState(() {
      _photoBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final store = ref.read(accountPhotoStoreProvider);
      if (remove) {
        await store.remove(owner);
      } else {
        final bytes = await ref.read(accountPhotoPickerProvider)();
        if (!_sameActor ||
            ref.read(accountPhotoOwnerProvider) != owner ||
            bytes == null) {
          return;
        }
        await store.save(owner, bytes);
      }
      if (_sameActor && ref.read(accountPhotoOwnerProvider) == owner) {
        ref.invalidate(accountPhotoProvider);
        setState(
          () => _message = remove
              ? 'Profile picture removed from this computer.'
              : 'Profile picture saved privately on this computer.',
        );
      }
    } on Object catch (error) {
      if (_sameActor) {
        setState(
          () => _error = switch (error) {
            AccountPhotoException(failure: AccountPhotoFailure.tooLarge) =>
              'Choose a JPG or PNG photo under 8 MB and at most 20 megapixels.',
            AccountPhotoException(failure: AccountPhotoFailure.invalidImage) =>
              'Choose a valid, still JPG or PNG photo.',
            _ => 'Your profile picture could not be saved securely. Try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionRevisionProvider);
    final gateway = ref.watch(foundationGatewayProvider);
    final user = gateway?.currentUser;
    if (user == null || user.id != _actor) {
      return AlertDialog(
        title: const Text('Account changed'),
        content: const Text(
          'Close this profile and open the current account again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final photo = ref.watch(accountPhotoProvider);
    final preferences = ref.watch(appPreferencesProvider).value;
    final busy = _saving || _photoBusy;
    return AlertDialog(
      title: const Text('Your profile'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: JentraColors.navy800,
                    child: photo.value == null
                        ? Text(
                            userInitials(name: _name.text, email: user.email),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          )
                        : ClipOval(
                            child: Image.memory(
                              photo.value!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              gaplessPlayback: false,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.person_outline,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('profile-change-photo'),
                      onPressed: busy ? null : _changePhoto,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _photoBusy ? 'Saving picture…' : 'Choose picture',
                      ),
                    ),
                    if (photo.value != null || photo.hasError)
                      TextButton(
                        key: const Key('profile-remove-photo'),
                        onPressed: busy
                            ? null
                            : () => _changePhoto(remove: true),
                        child: const Text('Remove picture'),
                      ),
                  ],
                ),
                const Text(
                  'Your picture is saved privately on this computer. JPG or PNG, up to 8 MB.',
                  textAlign: TextAlign.center,
                ),
                if (photo.hasError)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The saved picture could not be opened. You can replace or remove it.',
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('profile-name'),
                  controller: _name,
                  enabled: !busy,
                  maxLength: 100,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your name.'
                      : value.trim().runes.length > 100
                      ? 'Use a name with at most 100 Unicode characters.'
                      : RegExp(r'[\x00-\x1f\x7f\u2028\u2029]').hasMatch(value)
                      ? 'Use a name without control characters.'
                      : null,
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Sign-in email'),
                  child: SelectableText(user.email ?? 'No email is available'),
                ),
                const SizedBox(height: 20),
                const Text('App preferences'),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark appearance'),
                  value: preferences?.themeMode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(appPreferencesProvider.notifier).toggleTheme(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compact layout'),
                  value: preferences?.density == JentraDensity.compact,
                  onChanged: (_) =>
                      ref.read(appPreferencesProvider.notifier).toggleDensity(),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Account security'),
                  subtitle: Text(
                    gateway?.currentAssurance() == MfaAssurance.aal2
                        ? 'Multi-factor authentication is verified for this session.'
                        : 'Multi-factor authentication is required before privileged business access.',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showDesktopBuildInformation(context),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('About Jentra OS'),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: TextStyle(color: context.jentraColors.danger),
                    ),
                  ),
                ],
                if (_message case final message?) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(message)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          key: const Key('profile-save'),
          onPressed: busy ? null : _saveName,
          child: Text(_saving ? 'Saving…' : 'Save name'),
        ),
      ],
    );
  }
}
