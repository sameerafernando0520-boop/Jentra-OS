import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/analytics_platform.dart';

void main() {
  const tenant = '10000000-0000-0000-0000-000000000001';
  const start = '2026-10-01T00:00:00.000000Z';
  Map<String, Object?> projection({required String end}) => {
    'state': 'available',
    'tenantId': tenant,
    'metricCode': 'ai.tokens',
    'periodStart': start,
    'periodEnd': end,
    'limit': '100',
    'settled': '50',
    'reserved': '10',
    'remaining': '40',
    'generatedAt': '2026-11-02T00:00:00.000000Z',
  };
  Future<Map<String, Object?>> read(Map<String, Object?> raw) =>
      SupabaseWave5ControlGateway.injected(
        (_, _) async => raw,
      ).usage(tenant, 'ai.tokens', start);

  test('rejects an empty authoritative allowance period', () async {
    await expectLater(read(projection(end: start)), throwsFormatException);
  });

  test('rejects an inverted authoritative allowance period', () async {
    await expectLater(
      read(projection(end: '2026-09-30T23:59:59.999999Z')),
      throwsFormatException,
    );
  });

  test('retains historical allowance observed after period end', () async {
    final result = await read(projection(end: '2026-11-01T00:00:00Z'));
    expect(result['remaining'], '40');
    expect(result['generatedAt'], '2026-11-02T00:00:00.000000Z');
  });

  test('accepts the smallest positive microsecond period', () async {
    final result = await read(projection(end: '2026-10-01T00:00:00.000001Z'));
    expect(result['remaining'], '40');
  });

  test('keeps exact arithmetic and requested period validation', () async {
    final raw = projection(end: '2026-11-01T00:00:00Z');
    await expectLater(read({...raw, 'remaining': '41'}), throwsFormatException);
    await expectLater(
      read({...raw, 'periodStart': '2026-10-02T00:00:00Z'}),
      throwsFormatException,
    );
  });
}
