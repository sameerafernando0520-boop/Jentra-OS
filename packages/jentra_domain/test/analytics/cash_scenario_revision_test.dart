import 'package:jentra_domain/analytics.dart';
import 'package:test/test.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
void main() {
  final scope = ProcessMetricScope(tenantId: id(1), legalEntityId: id(2));
  test(
    'frozen assumptions copy nested inputs and never rewrite the original obligation',
    () {
      final overrides = {
        id(4): {
          'dueDate': '2026-10-03',
          'remainingUnits': '9007199254740993',
          'reasonCode': 'collection_delay',
        },
      };
      final r = CashScenarioRevision(
        id: id(3),
        scope: scope,
        sourceHash: 'a' * 64,
        horizonStart: '2026-10-01',
        horizonEnd: '2026-11-01',
        recordedThrough: '2026-10-01T00:00:00Z',
        overrides: overrides,
      );
      overrides[id(4)]!['remainingUnits'] = '0';
      final original = CashObligation(
        scope: scope,
        provider: 'receivables',
        id: id(4),
        currency: 'LKR',
        dueDate: '2026-10-02',
        remainingUnits: BigInt.one,
        inflow: true,
        publicationId: id(5),
        sourceVersion: '1',
      );
      expect(
        r.apply([original]).single.remainingUnits,
        BigInt.parse('9007199254740993'),
      );
      expect(original.remainingUnits, BigInt.one);
      expect(
        () => r.overrides[id(4)]!['remainingUnits'] = '0',
        throwsUnsupportedError,
      );
    },
  );
  test(
    'unknown source override and unreviewed reason cannot invent a cash flow',
    () {
      final r = CashScenarioRevision(
        id: id(3),
        scope: scope,
        sourceHash: 'a' * 64,
        horizonStart: '2026-10-01',
        horizonEnd: '2026-11-01',
        recordedThrough: '2026-10-01T00:00:00Z',
        overrides: {
          id(4): {
            'dueDate': '2026-10-03',
            'remainingUnits': '1',
            'reasonCode': 'reviewed_amount',
          },
        },
      );
      expect(() => r.apply([]), throwsFormatException);
    },
  );
  test(
    'recovery round trip keeps exact units and refuses extra private fields',
    () {
      final r = CashScenarioRevision(
        id: id(3),
        scope: scope,
        sourceHash: 'a' * 64,
        horizonStart: '2026-10-01',
        horizonEnd: '2026-11-01',
        recordedThrough: '2026-10-01T00:00:00Z',
        overrides: {},
      );
      expect(
        CashScenarioRevision.fromJson(scope, r.toJson()).sourceHash,
        r.sourceHash,
      );
      expect(
        () => CashScenarioRevision.fromJson(scope, {
          ...r.toJson(),
          'accessToken': 'private',
        }),
        throwsFormatException,
      );
    },
  );
}
