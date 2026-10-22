import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/developer_tools.dart';
import 'package:jentra_desktop/src/features/account/account_photo.dart';
import 'package:jentra_desktop/src/features/account/account_profile.dart';
import 'package:jentra_desktop/src/shell/jentra_shell.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-4000-8000-000000000001';
const _otherActor = '10000000-0000-4000-8000-000000000002';
const _owner = (
  project: 'https://profile-development.supabase.co',
  actor: _actor,
);
const _config = RuntimeConfig(
  environment: 'development',
  supabaseUrl: 'https://profile-development.supabase.co',
  supabasePublishableKey: 'synthetic-public-key',
);
final _project = StateProvider<RuntimeConfig>((ref) => _config);

Uint8List _thumbnail(int red, int green, int blue) {
  final pixels = img.Image(width: 256, height: 256, numChannels: 3);
  img.fill(pixels, color: img.ColorRgb8(red, green, blue));
  return Uint8List.fromList(img.encodeJpg(pixels));
}

class _MemoryPhotoStore implements AccountPhotoStore {
  final values = <AccountPhotoOwner, Uint8List>{};
  final saved = <AccountPhotoOwner>[];
  final removed = <AccountPhotoOwner>[];
  Object? failure;

  @override
  Future<Uint8List?> read(AccountPhotoOwner owner) async => values[owner];
  @override
  Future<void> save(AccountPhotoOwner owner, Uint8List bytes) async {
    if (failure != null) throw failure!;
    saved.add(owner);
    values[owner] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(AccountPhotoOwner owner) async {
    if (failure != null) throw failure!;
    removed.add(owner);
    values.remove(owner);
  }
}

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late _MemoryPhotoStore store;
  late Uint8List redPhoto, bluePhoto;
  String currentActor = _actor;
  String displayName = 'Nimali Silva';
  bool failUpdate = false;
  final updates = <http.Request>[];

  Map<String, Object?> user() => {
    'id': currentActor,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': currentActor == _actor
        ? 'nimali@example.test'
        : 'other@example.test',
    'created_at': '2026-10-22T00:00:00Z',
    'app_metadata': <String, Object?>{},
    'user_metadata': {'full_name': displayName},
  };

  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    redPhoto = _thumbnail(230, 20, 20);
    bluePhoto = _thumbnail(20, 20, 230);
  });

  setUp(() async {
    currentActor = _actor;
    displayName = 'Nimali Silva';
    failUpdate = false;
    updates.clear();
    store = _MemoryPhotoStore();
    FlutterSecureStorage.setMockInitialValues({});
    client = SupabaseClient(
      _config.supabaseUrl,
      _config.supabasePublishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user') && request.method == 'PUT') {
          updates.add(request);
          if (failUpdate) {
            return http.Response(
              jsonEncode({
                'msg': 'private-provider-diagnostic',
                'code': 'validation_failed',
              }),
              400,
              headers: {
                'content-type': 'application/json',
                'x-supabase-api-version': '2024-01-01',
              },
            );
          }
          displayName =
              ((jsonDecode(request.body) as Map)['data'] as Map)['full_name']
                  as String;
          return http.Response(
            jsonEncode(user()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (!request.url.path.endsWith('/token')) {
          throw StateError('Unexpected mock account route');
        }
        final claims = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'sub': currentActor,
                  'aal': 'aal2',
                  'exp':
                      DateTime.now()
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch ~/
                      1000,
                }),
              ),
            )
            .replaceAll('=', '');
        return http.Response(
          jsonEncode({
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
            'refresh_token': 'synthetic-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': user(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'nimali@example.test',
      password: 'synthetic-password',
    );
    gateway = SupabaseFoundationGateway(client);
  });
  tearDown(() async => client.dispose());

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    Future<Uint8List?> Function()? pick,
    bool shell = false,
    double textScale = 1,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => shell
              ? const JentraShell(child: Text('Workspace content'))
              : Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const Key('open-profile'),
                      onPressed: () => showAccountProfile(context),
                      child: const Text('Open profile'),
                    ),
                  ),
                ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWith((ref) => ref.watch(_project)),
          foundationGatewayProvider.overrideWithValue(gateway),
          accountPhotoStoreProvider.overrideWithValue(store),
          accountPhotoPickerProvider.overrideWithValue(
            pick ?? () async => redPhoto,
          ),
          tenantListProvider.overrideWithBuild((ref, notifier) async => []),
          businessCapabilitiesProvider.overrideWith((ref) async => {}),
          developerToolsEnabledProvider.overrideWithValue(false),
          appPreferencesProvider.overrideWithBuild(
            (ref, notifier) async => const AppPreferences(
              themeMode: ThemeMode.light,
              density: JentraDensity.comfortable,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: JentraTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder portrait() => find.descendant(
    of: find.byType(AccountProfileDialog),
    matching: find.byType(Image),
  );

  test(
    'normalizer centre-crops real pixels into a bounded metadata-free JPEG',
    () {
      final source = img.Image(
        width: 400,
        height: 200,
        numChannels: 3,
        textData: {'Description': 'synthetic-private-photo-metadata'},
      );
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      img.fillRect(
        source,
        x1: 100,
        y1: 0,
        x2: 299,
        y2: 199,
        color: img.ColorRgb8(0, 230, 0),
      );
      source.exif.imageIfd.imageDescription =
          'synthetic-private-photo-metadata';
      final normalized = normalizeAccountPhoto(
        Uint8List.fromList(img.encodePng(source)),
      );
      expect(
        normalized.length,
        lessThanOrEqualTo(SecureAccountPhotoStore.maximumBytes),
      );
      final decoded = img.decodeJpg(normalized)!;
      expect((decoded.width, decoded.height, decoded.numFrames), (256, 256, 1));
      expect(decoded.getPixel(128, 128).g, greaterThan(200));
      expect(decoded.getPixel(5, 128).r, lessThan(40));
      expect(decoded.exif.imageIfd.imageDescription, isNull);
      expect(decoded.textData ?? {}, isEmpty);
      expect(
        latin1.decode(normalized),
        isNot(contains('synthetic-private-photo-metadata')),
      );
    },
  );

  test('normalizer rejects malformed files and byte or dimension limits', () {
    expect(
      () => normalizeAccountPhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(
        isA<AccountPhotoException>().having(
          (e) => e.failure,
          'failure',
          AccountPhotoFailure.invalidImage,
        ),
      ),
    );
    expect(
      () => normalizeAccountPhoto(Uint8List(8 * 1024 * 1024 + 1)),
      throwsA(
        isA<AccountPhotoException>().having(
          (e) => e.failure,
          'failure',
          AccountPhotoFailure.tooLarge,
        ),
      ),
    );
    final wide = img.Image(width: 8193, height: 1);
    expect(
      () => normalizeAccountPhoto(Uint8List.fromList(img.encodePng(wide))),
      throwsA(
        isA<AccountPhotoException>().having(
          (e) => e.failure,
          'failure',
          AccountPhotoFailure.tooLarge,
        ),
      ),
    );
  });

  test('protected photo storage isolates actor and project and persists across instances', () async {
    const protected = SecureAccountPhotoStore();
    const other = (
      project: 'https://profile-development.supabase.co',
      actor: _otherActor,
    );
    const otherProject = (
      project: 'https://another-development.supabase.co',
      actor: _actor,
    );
    await protected.save(_owner, redPhoto);
    await protected.save(other, bluePhoto);
    await protected.save(otherProject, redPhoto);
    const restored = SecureAccountPhotoStore();
    expect(await restored.read(_owner), orderedEquals(redPhoto));
    expect(await restored.read(other), orderedEquals(bluePhoto));
    expect(await restored.read(otherProject), orderedEquals(redPhoto));
    final keys = await const FlutterSecureStorage().readAll();
    expect(keys, hasLength(3));
    expect(
      keys.keys.every(
        (key) => key.startsWith('jentra.desktop.account-photo.v1.'),
      ),
      isTrue,
    );
    expect(keys.keys.join(), isNot(contains(_actor)));
    expect(keys.keys.join(), isNot(contains('supabase.co')));
    await restored.remove(_owner);
    expect(await protected.read(_owner), isNull);
    expect(await protected.read(other), orderedEquals(bluePhoto));
    expect(await protected.read(otherProject), orderedEquals(redPhoto));
  });

  test(
    'protected store rejects unnormalized bytes and malformed saved data',
    () async {
      const protected = SecureAccountPhotoStore();
      await expectLater(
        protected.save(_owner, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AccountPhotoException>()),
      );
      await protected.save(_owner, redPhoto);
      final keys = await const FlutterSecureStorage().readAll();
      await const FlutterSecureStorage().write(
        key: keys.keys.single,
        value: 'not-base64-image',
      );
      await expectLater(
        protected.read(_owner),
        throwsA(
          isA<AccountPhotoException>().having(
            (e) => e.failure,
            'failure',
            AccountPhotoFailure.storageUnavailable,
          ),
        ),
      );
    },
  );

  testWidgets(
    'choose saves portrait and a restarted profile restores and removes it',
    (tester) async {
      await mount(tester);
      await open(tester);
      expect(portrait(), findsNothing);
      await tap(tester, 'profile-change-photo');
      expect(store.saved, [_owner]);
      expect(portrait(), findsOneWidget);
      expect(
        find.text('Profile picture saved privately on this computer.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      await open(tester);
      expect(portrait(), findsOneWidget);
      await tap(tester, 'profile-remove-photo');
      expect(store.removed, [_owner]);
      expect(store.values, isEmpty);
      expect(portrait(), findsNothing);
    },
  );

  testWidgets(
    'cancelled picker retains the previous portrait without writing',
    (tester) async {
      store.values[_owner] = redPhoto;
      await mount(tester, pick: () async => null);
      await open(tester);
      await tap(tester, 'profile-change-photo');
      expect(store.saved, isEmpty);
      expect(store.removed, isEmpty);
      expect(store.values[_owner], orderedEquals(redPhoto));
      expect(portrait(), findsOneWidget);
    },
  );

  for (final change in ['actor', 'project', 'dispose']) {
    testWidgets('pending picker cannot write after $change changes', (
      tester,
    ) async {
      final selected = Completer<Uint8List?>();
      final container = await mount(tester, pick: () => selected.future);
      await open(tester);
      await tester.tap(find.byKey(const Key('profile-change-photo')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profile-save')))
            .onPressed,
        isNull,
      );
      if (change == 'actor') {
        currentActor = _otherActor;
        await client.auth.signInWithPassword(
          email: 'other@example.test',
          password: 'synthetic-password',
        );
        await tester.pumpAndSettle();
        expect(find.text('Account changed'), findsOneWidget);
      } else if (change == 'project') {
        container.read(_project.notifier).state = const RuntimeConfig(
          environment: 'development',
          supabaseUrl: 'https://other-project.supabase.co',
          supabasePublishableKey: 'synthetic-public-key',
        );
        await tester.pump();
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      selected.complete(bluePhoto);
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      expect(store.values, isEmpty);
      expect(portrait(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed portrait save preserves the prior photo and hides diagnostics',
    (tester) async {
      store.values[_owner] = redPhoto;
      store.failure = StateError('private-photo-storage-diagnostic');
      await mount(tester, pick: () async => bluePhoto);
      await open(tester);
      await tap(tester, 'profile-change-photo');
      expect(
        find.text(
          'Your profile picture could not be saved securely. Try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('private-photo-storage-diagnostic'),
        findsNothing,
      );
      expect(store.values[_owner], orderedEquals(redPhoto));
      expect(portrait(), findsOneWidget);
    },
  );

  testWidgets(
    'name save sends only trimmed profile metadata and updates current account',
    (tester) async {
      await mount(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        '  Nimali Jayasinghe  ',
      );
      await tap(tester, 'profile-save');
      expect(updates, hasLength(1));
      expect((jsonDecode(updates.single.body) as Map)['data'], {
        'full_name': 'Nimali Jayasinghe',
      });
      expect(
        gateway.currentUser?.userMetadata?['full_name'],
        'Nimali Jayasinghe',
      );
      expect(find.text('Your name has been updated.'), findsOneWidget);
    },
  );

  testWidgets(
    'name failure retains the draft and allows retry without provider details',
    (tester) async {
      failUpdate = true;
      await mount(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'My retained draft',
      );
      await tap(tester, 'profile-save');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('profile-name')))
            .controller!
            .text,
        'My retained draft',
      );
      expect(gateway.currentUser?.userMetadata?['full_name'], 'Nimali Silva');
      expect(
        find.text(
          'Your name could not be saved. Check the connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private-provider-diagnostic'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profile-save')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('account menu opens profile with the saved image at 200% text', (
    tester,
  ) async {
    store.values[_owner] = redPhoto;
    final boundary = GlobalKey();
    await mount(tester, shell: true, textScale: 2, boundary: boundary);
    final account = find.byKey(const ValueKey('account-menu'));
    expect(
      find.descendant(of: account, matching: find.byType(Image)),
      findsOneWidget,
    );
    await tester.tap(account);
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('About Jentra OS'), findsOneWidget);
    await tester.tap(find.text('Your profile'));
    await tester.pumpAndSettle();
    expect(portrait(), findsOneWidget);
    expect(tester.takeException(), isNull);
    final dir = Platform.environment['W5_ACCOUNT_PROFILE_FRAME_DIR'];
    if (dir != null) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File('$dir/account-profile-1024-720-light-200.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.ensureVisible(find.byKey(const Key('profile-name')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-name')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
