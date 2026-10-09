import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';

class Files implements ReportExportFiles {
  bool wrote = false;
  void Function()? onChoose;
  @override
  Future<String?> choose(String fileName) async {
    onChoose?.call();
    return 'synthetic-selected-path';
  }

  @override
  Future<void> write(String target, Uint8List bytes, String mimeType) async {
    wrote = true;
  }
}

void main() {
  final scope = TenantContext(
    tenantId: id(1),
    legalEntityId: id(2),
    branchId: id(3),
    actorId: id(4),
  );
  Future<Map<String, Object?>> wire() async {
    final document = {
      'version': 1,
      'metadata': {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'working_branch_id': scope.branchId,
        'actor_id': scope.actorId,
        'row_count': 1,
      },
      'rows': [
        {'amount': '9007199254740.993001', 'currency': 'LKR'},
      ],
    };
    final text = jsonEncode(document),
        hash = await ReportExportCodec.hash(utf8.encode(text));
    final artifact = await const ReportExportCodec().encode(
      document,
      format: 'csv',
      exportId: id(5),
      preparedAt: '2026-10-01T00:00:00Z',
      sourceHash: hash,
    );
    return {
      'id': id(5),
      'canonicalText': text,
      'sourceHash': hash,
      'fileHash': artifact.sha256,
      'preparedAt': '2026-10-01T00:00:00Z',
      'format': 'csv',
      'fileName': 'synthetic.csv',
    };
  }

  test(
    'governed reopen reproduces exact registered bytes; revocation during chooser blocks write',
    () async {
      var allowed = true;
      final files = Files();
      final gateway = GovernedAnalyticsExport((_, _) async {
        if (!allowed) throw StateError('revoked');
        return wire();
      }, files);
      final result = await gateway.reopen(scope, id(5));
      expect(utf8.decode(result.$1.bytes), contains('9007199254740.993001'));
      files.onChoose = () => allowed = false;
      await expectLater(
        gateway.download(scope, id(5), () => true),
        throwsStateError,
      );
      expect(files.wrote, isFalse);
    },
  );
  test('altered registered file digest cannot be downloaded', () async {
    final files = Files(),
        gateway = GovernedAnalyticsExport(
          (_, _) async => {...await wire(), 'fileHash': 'a' * 64},
          Files(),
        );
    await expectLater(gateway.reopen(scope, id(5)), throwsFormatException);
    expect(files.wrote, isFalse);
  });
}
