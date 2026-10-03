import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';

class _Access extends ChangeNotifier implements OperationalReadAccess {
  int epoch = 0;
  bool permitted = true;
  @override
  int get readAccessEpoch => epoch;
  @override
  bool currentRead(int captured) => permitted && captured == epoch;
  @override
  void denyReadAccess() {
    permitted = false;
    epoch++;
    notifyListeners();
  }

  void reconnect() {
    epoch++;
    permitted = true;
    notifyListeners();
  }
}

void main() {
  testWidgets('a post-pop epoch change rejects a previously selected result', (
    tester,
  ) async {
    final access = _Access();
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext origin;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            origin = context;
            return const Scaffold(body: Text('Origin'));
          },
        ),
      ),
    );
    final selection = showOperationalReadDialog<String>(
      origin,
      access,
      (_) => const AlertDialog(content: Text('Private selected source')),
    );
    await tester.pumpAndSettle();
    // Pop and revoke synchronously, before the awaiting caller resumes.
    navigator.currentState!.pop('selected-original-source');
    access.denyReadAccess();
    access.reconnect();
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });

  testWidgets('an unchanged originating epoch accepts the selected result', (
    tester,
  ) async {
    final access = _Access();
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext origin;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            origin = context;
            return const Scaffold(body: Text('Origin'));
          },
        ),
      ),
    );
    final selection = showOperationalReadDialog<String>(
      origin,
      access,
      (_) => const AlertDialog(content: Text('Private selected source')),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop('selected-original-source');
    await tester.pumpAndSettle();
    expect(await selection, 'selected-original-source');
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });
}
