import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_document_export_io.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('employee-export-regression');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'chooseDestination'
              ? 'opaque-destination'
              : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('revoked synchronous lease after server check never releases bytes to native write', () async {
    final exporter = AndroidEmployeeDocumentExporter(
      channel: channel,
      isAndroid: () => true,
    );
    await expectLater(
      exporter.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/pdf',
        reauthorize: () async => true,
        stillAuthorized: () => false,
      ),
      throwsA(
        isA<EmployeeFailure>().having(
          (error) => error.code,
          'code',
          'SESSION_CHANGED',
        ),
      ),
    );
    expect(calls.map((call) => call.method), [
      'chooseDestination',
      'discardDestination',
    ]);
    expect((calls.first.arguments as Map).containsKey('bytes'), isFalse);
  });
  test('chosen handle and fresh authority precede bytes and handle is discarded afterwards', () async {
    final exporter = AndroidEmployeeDocumentExporter(
      channel: channel,
      isAndroid: () => true,
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(
      await exporter.save(
        bytes: bytes,
        mimeType: 'application/pdf',
        reauthorize: () async {
          expect(calls.map((call) => call.method), ['chooseDestination']);
          return true;
        },
        stillAuthorized: () => true,
      ),
      isTrue,
    );
    expect(calls.map((call) => call.method), [
      'chooseDestination',
      'writeDocument',
      'discardDestination',
    ]);
    expect(calls[1].arguments, {
      'handle': 'opaque-destination',
      'bytes': bytes,
    });
    expect(calls.first.arguments, {
      'mimeType': 'application/pdf',
      'name': 'Jentra-document.pdf',
    });
  });
  test(
    'cancelled chooser never performs authorization or writes bytes',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final exporter = AndroidEmployeeDocumentExporter(
        channel: channel,
        isAndroid: () => true,
      );
      expect(
        await exporter.save(
          bytes: Uint8List.fromList([1]),
          mimeType: 'application/pdf',
          reauthorize: () async => throw StateError('Must not run'),
          stillAuthorized: () => true,
        ),
        isFalse,
      );
      expect(calls.map((call) => call.method), ['chooseDestination']);
    },
  );
}
