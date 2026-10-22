import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/build_identity.dart';
import 'package:jentra_desktop/src/developer_tools.dart';
import 'package:jentra_desktop/src/features/operations/operational_controller.dart';
import 'package:jentra_desktop/src/features/operations/operational_dashboard.dart';
import 'package:jentra_desktop/src/router.dart';
import 'package:jentra_desktop/src/shell/build_information_dialog.dart';
import 'package:jentra_desktop/src/shell/jentra_shell.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_desktop/src/shell/workspace_navigation.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-4000-8000-000000000001';
const _email = 'synthetic-sensitive-account@example.test';
const _publicKey = 'synthetic-publishable-key-do-not-copy';
const _config = RuntimeConfig(
  environment: 'development',
  supabaseUrl: 'https://selected-development.supabase.co',
  supabasePublishableKey: _publicKey,
);
const _identity = DesktopBuildIdentity(
  version: '2.3.4+17',
  revision: '0123456789abcdef',
  builtAtUtc: '2026-10-22T08:30:00Z',
  channel: 'Development acceptance',
  projectRef: 'selected-development',
  sourceSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);
const _scope = BusinessScopeState(
  tenants: [
    TenantSummary(
      id: 'tenant-a',
      name: 'First permitted business',
      slug: 'first',
      status: 'active',
      membershipStatus: 'active',
    ),
    TenantSummary(
      id: 'tenant-b',
      name: 'Selected synthetic business',
      slug: 'selected',
      status: 'active',
      membershipStatus: 'active',
    ),
  ],
  legalEntities: [
    LegalEntitySummary(
      id: 'entity-b',
      tenantId: 'tenant-b',
      name: 'Selected legal entity',
      code: 'SLE',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  branches: [
    BranchSummary(
      id: 'branch-b1',
      tenantId: 'tenant-b',
      legalEntityId: 'entity-b',
      name: 'Eastern depot',
      code: 'EAST',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
    BranchSummary(
      id: 'branch-b2',
      tenantId: 'tenant-b',
      legalEntityId: 'entity-b',
      name: 'Selected western branch',
      code: 'WEST',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  tenantId: 'tenant-b',
  legalEntityId: 'entity-b',
  branchId: 'branch-b2',
);
const _caps = {
  'finance.view',
  'finance.receivables.view',
  'inventory.stock.view',
  'crm.leads.view',
};
final _access = StateProvider<AsyncValue<Set<String>>>(
  (ref) => const AsyncData(_caps),
);
final _connection = StateProvider<ConnectivityState>(
  (ref) => ConnectivityState.online,
);

class _DashboardGateway implements OperationalGateway {
  final scopes = <TenantContext>[];
  Completer<Map<String, Object?>>? held;
  Object? failure;
  Map<String, Object?> data = {
    'generated_at': '2026-10-22T08:30:00Z',
    'cards': [
      {'kind': 'lead', 'count': '9007199254740993'},
      {'kind': 'manual_journal', 'count': '0'},
    ],
    'metrics': [
      {
        'kind': 'ar_aging',
        'as_of': '2026-10-22',
        'generated_at': '2026-10-22T08:30:00Z',
        'destination': '/receivables',
        'data': {
          'buckets': [
            {
              'currency_code': 'LKR',
              'bucket': 'current',
              'amount': '900719925474.099999',
              'item_count': '3',
            },
            {
              'currency_code': 'USD',
              'bucket': 'current',
              'amount': '12.300001',
              'item_count': '1',
            },
          ],
        },
      },
    ],
  };

  @override
  Future<Map<String, Object?>> dashboard(TenantContext scope) async {
    scopes.add(scope);
    if (held != null) return held!.future;
    if (failure != null) throw failure!;
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway foundation;

  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${fonts}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() async {
    client = SupabaseClient(
      _config.supabaseUrl,
      _publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (!request.url.path.endsWith('/token')) {
          throw StateError('Unexpected fixture request');
        }
        final claims = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'sub': _actor,
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
            'user': {
              'id': _actor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': _email,
              'created_at': '2026-10-22T00:00:00Z',
              'app_metadata': <String, Object?>{},
              'user_metadata': {'full_name': 'Nimali Silva'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: _email,
      password: 'synthetic-password-only',
    );
    foundation = SupabaseFoundationGateway(client);
  });
  tearDown(() async => client.dispose());

  Future<ProviderContainer> mount(
    WidgetTester tester,
    _DashboardGateway gateway, {
    bool shell = true,
    bool actualRouter = false,
    Size size = const Size(1920, 1080),
    double textScale = 1,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (_, _, child) =>
              shell ? JentraShell(child: child) : Scaffold(body: child),
          routes: [
            GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
            GoRoute(
              path: '/dashboard',
              builder: (_, _) => const OperationalDashboard(),
            ),
            GoRoute(
              path: '/finance/budgets',
              builder: (_, _) => const Text('Nested financial workspace'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(_config),
          foundationGatewayProvider.overrideWithValue(foundation),
          sessionAssuranceProvider.overrideWithValue(MfaAssurance.aal2),
          authenticatedActorProvider.overrideWith(
            (ref) => Stream.value(_actor),
          ),
          tenantListProvider.overrideWithBuild(
            (ref, notifier) async => _scope.tenants,
          ),
          businessScopeProvider.overrideWithBuild(
            (ref, notifier) async => _scope,
          ),
          businessCapabilitiesProvider.overrideWith((ref) {
            final value = ref.watch(_access);
            if (value.isLoading) return Completer<Set<String>>().future;
            if (value.hasError) {
              return Future<Set<String>>.error(value.error!, value.stackTrace);
            }
            return value.requireValue;
          }),
          connectivityStateProvider.overrideWith(
            (ref) => Stream.value(ref.watch(_connection)),
          ),
          operationalGatewayProvider.overrideWithValue(gateway),
          developerToolsEnabledProvider.overrideWithValue(false),
          desktopBuildIdentityProvider.overrideWithValue(_identity),
          appPreferencesProvider.overrideWithBuild(
            (ref, notifier) async => const AppPreferences(
              themeMode: ThemeMode.light,
              density: JentraDensity.comfortable,
            ),
          ),
        ],
        child: actualRouter
            ? const JentraApp()
            : MaterialApp.router(
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
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    );
  }

  test('all permitted destinations occur exactly once in workspace groups', () {
    for (final access in <Set<String>?>[
      null,
      {},
      _caps,
      {'assurance.evidence.view', 'people.employees.view'},
    ]) {
      final permitted = visibleJentraDestinations(access);
      final groups = groupWorkspaceDestinations(permitted);
      final paths = groups
          .expand((group) => group.items)
          .map((item) => item.path)
          .toList();
      expect(paths, unorderedEquals(permitted.map((item) => item.path)));
      expect(paths.toSet(), hasLength(paths.length));
      expect(groups.every((group) => group.items.isNotEmpty), isTrue);
    }
  });

  test(
    'developer tools are limited to disconnected nonproduction debug builds',
    () {
      for (final scenario in [
        (
          label: 'offline developer debug',
          debug: true,
          connected: false,
          production: false,
          allowed: true,
        ),
        (
          label: 'installed offline preview',
          debug: false,
          connected: false,
          production: false,
          allowed: false,
        ),
        (
          label: 'installed development app',
          debug: false,
          connected: true,
          production: false,
          allowed: false,
        ),
        (
          label: 'installed production app',
          debug: false,
          connected: true,
          production: true,
          allowed: false,
        ),
        (
          label: 'connected debug app',
          debug: true,
          connected: true,
          production: false,
          allowed: false,
        ),
        (
          label: 'production debug app',
          debug: true,
          connected: false,
          production: true,
          allowed: false,
        ),
      ]) {
        expect(
          developerToolsAvailable(
            isDebugBuild: scenario.debug,
            connected: scenario.connected,
            production: scenario.production,
          ),
          scenario.allowed,
          reason: scenario.label,
        );
      }
    },
  );

  testWidgets('collapsed inventory group routes to a nested destination', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/inventory/counts',
      routes: [
        ShellRoute(
          builder: (_, state, child) => Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: WorkspaceNavigation(
                    destinations: const [
                      JentraDestination(
                        label: 'Stock counts',
                        path: '/inventory/counts',
                        icon: Icons.fact_check_outlined,
                      ),
                      JentraDestination(
                        label: 'Warehouse transfers',
                        path: '/inventory/transfers',
                        icon: Icons.swap_horiz,
                      ),
                    ],
                    currentPath: state.uri.path,
                    collapsed: true,
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/inventory/counts',
              builder: (_, _) => const Text('Count destination'),
            ),
            GoRoute(
              path: '/inventory/transfers',
              builder: (_, _) => const Text('Transfer destination'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: JentraTheme.dark(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Inventory'));
    await tester.pumpAndSettle();
    expect(find.text('Stock counts'), findsOneWidget);
    await tester.tap(find.text('Warehouse transfers'));
    await tester.pumpAndSettle();
    expect(find.text('Transfer destination'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/inventory/transfers',
    );
  });

  testWidgets(
    'connected shell shows selected scope and build without preview identity',
    (tester) async {
      await mount(tester, _DashboardGateway());
      expect(find.text('Selected synthetic business'), findsWidgets);
      expect(find.text('Selected legal entity'), findsOneWidget);
      expect(find.text('Selected western branch'), findsOneWidget);
      expect(find.text('First permitted business'), findsNothing);
      expect(find.text('Connected · 2.3.4+17'), findsOneWidget);
      expect(find.text('Preview data'), findsNothing);
      expect(find.textContaining('Shehan'), findsNothing);
      expect(find.text('Jentra Holdings'), findsNothing);
      expect(find.text('Design system'), findsNothing);
    },
  );

  testWidgets(
    'workspace branch selection updates the actual scope and dashboard read',
    (tester) async {
      final gateway = _DashboardGateway();
      final container = await mount(tester, gateway);
      await tester.tap(find.byKey(const ValueKey('workspace-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-branch-entity-b-branch-b2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eastern depot').last);
      await tester.pumpAndSettle();
      expect(
        container.read(businessScopeProvider).requireValue.branchId,
        'branch-b1',
      );
      expect(
        container.read(activeTenantContextProvider)?.branchId,
        'branch-b1',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Eastern depot'), findsOneWidget);
      expect(find.text('Selected western branch'), findsNothing);
      expect(gateway.scopes.last.branchId, 'branch-b1');
      expect(gateway.scopes.last.tenantId, 'tenant-b');
    },
  );

  testWidgets('About copies build diagnostics without keys or account data', (
    tester,
  ) async {
    await mount(tester, _DashboardGateway());
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Jentra OS'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopBuildInformationDialog), findsOneWidget);
    await tester.ensureVisible(find.text('Copy build information'));
    await tester.tap(find.text('Copy build information'));
    await tester.pump();
    expect(copied, contains('Version: 2.3.4+17'));
    expect(copied, contains('Revision: 0123456789abcdef'));
    expect(
      copied,
      contains('Configured workspace: selected-development.supabase.co'),
    );
    for (final secret in [
      _publicKey,
      _actor,
      _email,
      'synthetic-password-only',
      'synthetic-refresh',
    ]) {
      expect(copied, isNot(contains(secret)));
    }
    expect(copied, isNot(contains('Selected synthetic business')));
  });

  testWidgets(
    'configured sidebar palette and direct URL exclude developer catalogue',
    (tester) async {
      final container = await mount(
        tester,
        _DashboardGateway(),
        actualRouter: true,
        size: const Size(1440, 900),
      );
      expect(find.text('Design system'), findsNothing);
      expect(find.byTooltip('Design system'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Design system');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Design system'), findsNothing);
      expect(find.text('No commands match your search.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      router.go('/catalogue');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.text('Component catalogue'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard preserves server counts dates and separate exact currency amounts',
    (tester) async {
      final gateway = _DashboardGateway();
      await mount(tester, gateway, shell: false);
      expect(gateway.scopes.single.tenantId, 'tenant-b');
      expect(gateway.scopes.single.legalEntityId, 'entity-b');
      expect(gateway.scopes.single.branchId, 'branch-b2');
      await tester.scrollUntilVisible(find.text('9007199254740993'), 250);
      expect(find.text('9007199254740993'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('No records need action'), findsOneWidget);
      expect(find.text('Updated 22 Oct 2026, 08:30 UTC'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('900719925474.099999'),
        250,
      );
      expect(
        find.text('LKR · current · 900719925474.099999 · 3 open items'),
        findsOneWidget,
      );
      expect(
        find.text('USD · current · 12.300001 · 1 open items'),
        findsOneWidget,
      );
      expect(find.text('Preview metrics'), findsNothing);
      expect(find.text('Good morning, Shehan'), findsNothing);
      expect(find.text('LKR 12.84M'), findsNothing);
    },
  );

  for (final transition in [
    'offline',
    'access-loading',
    'access-error',
    'request-loading',
    'request-error',
  ]) {
    testWidgets('dashboard clears previously loaded counts on $transition', (
      tester,
    ) async {
      final gateway = _DashboardGateway();
      final container = await mount(tester, gateway, shell: false);
      await tester.scrollUntilVisible(find.text('9007199254740993'), 250);
      expect(find.text('9007199254740993'), findsOneWidget);
      switch (transition) {
        case 'offline':
          container.read(_connection.notifier).state =
              ConnectivityState.offline;
        case 'access-loading':
          container.read(_access.notifier).state = const AsyncLoading();
        case 'access-error':
          container.read(_access.notifier).state = AsyncError(
            StateError('private-access-diagnostic'),
            StackTrace.current,
          );
        case 'request-loading':
          gateway.held = Completer();
          container.invalidate(operationalDashboardProvider);
        case 'request-error':
          gateway.failure = StateError('private-dashboard-diagnostic');
          container.invalidate(operationalDashboardProvider);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('9007199254740993'), findsNothing);
      expect(find.textContaining('900719925474.099999'), findsNothing);
      expect(find.textContaining('private-access-diagnostic'), findsNothing);
      expect(find.textContaining('private-dashboard-diagnostic'), findsNothing);
      if (transition == 'offline') {
        expect(find.text('You are offline'), findsOneWidget);
      }
      if (transition == 'access-error') {
        expect(find.text('Access could not be checked'), findsOneWidget);
      }
      if (transition == 'request-error') {
        expect(find.text('Current work could not be loaded'), findsOneWidget);
      }
      if (gateway.held != null) {
        gateway.held!.complete({});
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('connected command centre fits at 200% text with real fonts', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await mount(
      tester,
      _DashboardGateway(),
      size: const Size(1024, 720),
      textScale: 2,
      boundary: boundary,
    );
    expect(find.byType(WorkspaceNavigation), findsOneWidget);
    expect(tester.takeException(), isNull);
    final dir = Platform.environment['W5_DESKTOP_COMPLETION_FRAME_DIR'];
    if (dir != null) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File('$dir/connected-command-centre-1024-720-light-200.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
