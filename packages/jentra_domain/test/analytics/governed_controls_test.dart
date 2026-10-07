import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/intelligence_control.dart';
import 'package:test/test.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
final scope = ProcessMetricScope(tenantId: id(1), legalEntityId: id(2));
final hash = 'a' * 64;

final class Hasher implements ProcessMetricHasher {
  Hasher(this.result);
  final String result;
  List<int>? bytes;
  @override
  Future<String> sha256(List<int> input) async {
    bytes = List.of(input);
    return result;
  }
}

AiProposalRevision proposal({int revision = 1}) => AiProposalRevision(
  id: id(3),
  proposerId: id(4),
  commandId: id(5),
  evidence: RedactedForecastEvidence(
    scope: scope,
    sourceId: id(6),
    sourceHash: hash,
    targetVersions: {id(7): '9007199254740993'},
  ),
  createdAt: '2026-10-06T00:00:00Z',
  expiresAt: '2026-10-06T01:00:00Z',
  horizonStart: '2026-10-01',
  horizonEnd: '2026-11-01',
  estimatedUnits: BigInt.from(100),
  parametersHash: hash,
  revision: revision,
);
ProposalApproval approval({int revision = 1, String? actor}) =>
    ProposalApproval(
      proposalId: id(3),
      revision: revision,
      parametersHash: hash,
      approverId: actor ?? id(8),
      approvedAt: '2026-10-06T00:01:00Z',
    );
void validate({
  AiProposalRevision? p,
  ProposalApproval? a,
  DateTime? now,
  bool online = true,
  bool mfa = true,
  bool approver = true,
  bool executor = true,
  bool entitlement = true,
  bool quota = true,
  Map<String, String>? targets,
}) => validateProposalExecution(
  p ?? proposal(),
  a ?? approval(),
  now: now ?? DateTime.utc(2026, 10, 6, 0, 2),
  online: online,
  approverMfa: mfa,
  liveApproverPermission: approver,
  liveExecutorPermission: executor,
  entitlement: entitlement,
  quotaReserved: quota,
  scope: scope,
  liveTargetVersions: targets ?? {id(7): '9007199254740993'},
);
void main() {
  test(
    'proposal canonical projection binds exact target strings and UTC precision',
    () async {
      final p = proposal(), h = Hasher(hash);
      await p.verifyHash(h);
      final c = jsonDecode(utf8.decode(h.bytes!)) as Map;
      expect(c['createdAt'], '2026-10-06T00:00:00.000000Z');
      expect((c['targets'] as Map)[id(7)], '9007199254740993');
      await expectLater(p.verifyHash(Hasher('b' * 64)), throwsFormatException);
    },
  );
  test(
    'redacted source evidence rejects malformed hashes, versions and row excess',
    () {
      RedactedForecastEvidence evidence(
        String digest,
        Map<String, String> targets,
      ) => RedactedForecastEvidence(
        scope: scope,
        sourceId: id(6),
        sourceHash: digest,
        targetVersions: targets,
      );
      expect(
        () => evidence('not-a-digest', {id(7): '1'}),
        throwsFormatException,
      );
      for (final version in ['01', '0', '9223372036854775808']) {
        expect(() => evidence(hash, {id(7): version}), throwsFormatException);
      }
      expect(
        () =>
            evidence(hash, {for (var i = 0; i < 10001; i++) id(i + 100): '1'}),
        throwsFormatException,
      );
      expect(evidence(hash, {id(7): '1'}).toJson()['sourceHash'], hash);
    },
  );
  test(
    'proposal expiry, horizon and budget guards reject unsupported execution bases',
    () {
      AiProposalRevision make({
        String expiry = '2026-10-06T01:00:00Z',
        String end = '2026-11-01',
        BigInt? units,
        int revision = 1,
      }) => AiProposalRevision(
        id: id(3),
        proposerId: id(4),
        commandId: id(5),
        evidence: proposal().evidence,
        createdAt: '2026-10-06T00:00:00Z',
        expiresAt: expiry,
        horizonStart: '2026-10-01',
        horizonEnd: end,
        estimatedUnits: units ?? BigInt.one,
        parametersHash: hash,
        revision: revision,
      );
      for (final expiry in ['2026-10-06T00:00:00Z', '2026-10-07T00:00:01Z']) {
        expect(() => make(expiry: expiry), throwsFormatException);
      }
      expect(() => make(end: '2028-01-01'), throwsFormatException);
      expect(() => make(units: BigInt.from(1000001)), throwsFormatException);
      expect(() => make(revision: 0), throwsFormatException);
    },
  );
  test(
    'negative quota basis, invalid trial and non-UTC trial checks fail closed',
    () {
      expect(
        () => quotaRemaining(-BigInt.one, BigInt.zero, []),
        throwsFormatException,
      );
      expect(
        () => SyntheticTrial(
          startsAt: '2026-10-06T00:00:00Z',
          endsAt: '2026-10-06T00:00:00Z',
          planCode: 'starter',
          seats: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => SyntheticTrial(
          startsAt: '2026-10-06T00:00:00Z',
          endsAt: '2026-10-07T00:00:00Z',
          planCode: 'starter',
          seats: 10001,
        ),
        throwsFormatException,
      );
      final trial = SyntheticTrial(
        startsAt: '2026-10-06T00:00:00Z',
        endsAt: '2026-10-07T00:00:00Z',
        planCode: 'starter',
        seats: 1,
      );
      expect(
        () => trial.activeAt(DateTime(2026, 10, 6)),
        throwsFormatException,
      );
    },
  );
  test(
    'invalid operational health and long-lived grants cannot create authority',
    () {
      expect(
        () => OperatorTenantGrant(
          id: id(10),
          operatorId: id(8),
          tenantId: id(1),
          reason: 'Synthetic investigation',
          issuedAt: '2026-10-06T00:00:00Z',
          expiresAt: '2026-10-06T01:00:01Z',
        ),
        throwsFormatException,
      );
      for (final code in ['private_business_rows', 'retry_count']) {
        expect(
          () => HealthProbe(
            code: code,
            observedAt: '2026-10-06T00:00:00Z',
            value: -BigInt.one,
            contractRevision: 1,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'current distinct exact approval and source revision permit validation only',
    () {
      expect(() => validate(), returnsNormally);
    },
  );
  test('self approval, edited revision and changed target denied', () {
    expect(() => validate(a: approval(actor: id(4))), throwsFormatException);
    expect(() => validate(p: proposal(revision: 2)), throwsFormatException);
    expect(
      () => validate(targets: {id(7): '9007199254740994'}),
      throwsFormatException,
    );
  });
  test('offline, lost MFA, permissions, entitlement and quota all block', () {
    for (final attempt in <void Function()>[
      () => validate(online: false),
      () => validate(mfa: false),
      () => validate(approver: false),
      () => validate(executor: false),
      () => validate(entitlement: false),
      () => validate(quota: false),
    ]) {
      expect(attempt, throwsFormatException);
    }
  });
  test('expiry boundary is exclusive and approval cannot precede creation', () {
    expect(
      () => validate(now: DateTime.utc(2026, 10, 6, 1)),
      throwsFormatException,
    );
    expect(
      () => validate(now: DateTime.utc(2026, 10, 6)),
      throwsFormatException,
    );
  });
  test('evidence excludes arbitrary source text and command is fixed', () {
    expect(
      proposal().evidence.toJson().keys,
      unorderedEquals([
        'sourceId',
        'sourceHash',
        'tenantId',
        'legalEntityId',
        'branchId',
        'targetVersions',
      ]),
    );
    expect(AiProposalRevision.commandCode, 'analytics.freeze_pipeline.v1');
    expect(
      () => proposal().evidence.targetVersions[id(9)] = '1',
      throwsUnsupportedError,
    );
  });
  test('unknown invocation keeps its exact quota reservation', () {
    final r = InvocationReservation(
      id: id(9),
      reservedUnits: BigInt.from(60),
      outcome: InvocationOutcome.unknown,
    );
    expect(
      quotaRemaining(BigInt.from(100), BigInt.from(30), [r]),
      BigInt.from(10),
    );
    expect(
      () => quotaRemaining(BigInt.from(100), BigInt.zero, [r, r]),
      throwsFormatException,
    );
  });
  test(
    'settlement cannot exceed reservation and over-limit allowance is explicit zero',
    () {
      expect(
        () => InvocationReservation(
          id: id(9),
          reservedUnits: BigInt.one,
          outcome: InvocationOutcome.settled,
          settledUnits: BigInt.two,
        ),
        throwsFormatException,
      );
      expect(quotaRemaining(BigInt.one, BigInt.two, []), BigInt.zero);
      final r = InvocationReservation(
        id: id(9),
        reservedUnits: BigInt.two,
        outcome: InvocationOutcome.settled,
        settledUnits: BigInt.one,
      );
      expect(r.outstanding, BigInt.zero);
    },
  );
  test('synthetic trial start inclusive and expiry exclusive', () {
    final t = SyntheticTrial(
      startsAt: '2026-10-01T00:00:00Z',
      endsAt: '2026-10-06T00:00:00Z',
      planCode: 'starter',
      seats: 5,
    );
    expect(t.activeAt(DateTime.utc(2026, 10, 1)), isTrue);
    expect(t.activeAt(DateTime.utc(2026, 10, 6)), isFalse);
  });
  test(
    'tenant owner cannot substitute for explicit operator authority or MFA',
    () {
      final g = OperatorTenantGrant(
        id: id(10),
        operatorId: id(8),
        tenantId: id(1),
        reason: 'Synthetic incident investigation',
        issuedAt: '2026-10-06T00:00:00Z',
        expiresAt: '2026-10-06T01:00:00Z',
      );
      expect(
        () => g.requireAccess(
          id(8),
          id(1),
          DateTime.utc(2026, 10, 6, 0, 2),
          operatorAuthority: false,
          mfa: true,
        ),
        throwsFormatException,
      );
      expect(
        () => g.requireAccess(
          id(8),
          id(2),
          DateTime.utc(2026, 10, 6, 0, 2),
          operatorAuthority: true,
          mfa: true,
        ),
        throwsFormatException,
      );
      expect(
        () => g.requireAccess(
          id(8),
          id(1),
          DateTime.utc(2026, 10, 6, 1),
          operatorAuthority: true,
          mfa: true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'stale or future probes are unknown, observed zero remains a real zero',
    () {
      final p = HealthProbe(
        code: 'retry_count',
        observedAt: '2026-10-06T00:00:00Z',
        value: BigInt.zero,
        contractRevision: 1,
      );
      expect(p.stateAt(DateTime.utc(2026, 10, 6, 0, 5)), 'observed');
      expect(p.stateAt(DateTime.utc(2026, 10, 6, 0, 6)), 'unknown');
      expect(p.stateAt(DateTime.utc(2026, 10, 5, 23)), 'unknown');
    },
  );
  test('missing or incompatible provider fails before dependent work', () {
    expect(
      () => const ProviderContract(
        code: 'model',
        revision: 1,
        ready: false,
        reason: 'Unconfigured',
      ).requireRevision(1),
      throwsFormatException,
    );
    expect(
      () => const ProviderContract(
        code: 'model',
        revision: 2,
        ready: true,
        reason: '',
      ).requireRevision(1),
      throwsFormatException,
    );
  });
}
