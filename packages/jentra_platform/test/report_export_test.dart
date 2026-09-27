import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> exportDocument() => {
  'version': 1,
  'metadata': {
    'id': 'report',
    'version': 1,
    'tenant_id': 't',
    'legal_entity_id': 'e',
    'branch_id': 'b',
    'working_branch_id': 'b',
    'actor_id': 'actor',
    'source_type': 'close',
    'source_id': 'report',
    'section': 'sources',
    'filters': {'component_key': 'GRNI:b'},
    'row_count': 1,
    'as_of': '2026-09-25',
    'generated_at': '2026-09-26T00:00:00Z',
    'currency_code': 'LKR',
  },
  'rows': [
    {
      'id': 'source',
      'value': '-9007199254.740993',
      'quantity': '0.000001',
      'name': '=HYPERLINK("bad")',
      'reference': 'Quoted, multiline\nreceipt',
      'detail': {'original_base_amount': '0.730000'},
    },
  ],
};
void main() {
  const codec = ReportExportCodec();
  Future<ReportExportArtifact> artifact(
    Map<String, Object?> d, {
    String format = 'xlsx',
  }) => codec.encode(
    d,
    format: format,
    exportId: 'export',
    preparedAt: '2026-09-26T00:00:00Z',
    sourceHash: 'a' * 64,
  );
  test(
    'CSV preserves exact signed amounts escaped quotes and frozen metadata',
    () async {
      final a = await artifact(exportDocument(), format: 'csv');
      final decoded = const SetupTabularCodec.reportExport().decodeCsv(a.bytes);
      final row = decoded.rows.last;
      expect(row[decoded.headers.indexOf('data_value')], '-9007199254.740993');
      expect(
        row[decoded.headers.indexOf('data_reference')],
        'Quoted, multiline\nreceipt',
      );
      expect(
        decoded.rows.first[decoded.headers.indexOf('report_as_of')],
        '2026-09-25',
      );
      expect(
        row[decoded.headers.indexOf('data_name')],
        startsWith("'=HYPERLINK"),
      );
      expect(a.rowCount, 1);
      expect(decoded.rowCount, 2);
    },
  );
  test(
    'XLSX uses string cells and no formulas while retaining negative exact values',
    () async {
      final a = await artifact(exportDocument());
      final zip = ZipDecoder().decodeBytes(a.bytes);
      final xml = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(xml, contains('t="inlineStr"'));
      expect(xml, contains('-9007199254.740993'));
      expect(xml, contains('=HYPERLINK'));
      expect(xml, isNot(contains('<f>')));
      final decoded = const SetupTabularCodec.reportExport().decodeXlsx(
        a.bytes,
      );
      expect(
        decoded.rows.last[decoded.headers.indexOf('data_quantity')],
        '0.000001',
      );
    },
  );
  test(
    'nested exact source evidence and deterministic byte hash survive encoding',
    () async {
      final first = await artifact(exportDocument()),
          second = await artifact(exportDocument());
      expect(first.sha256, second.sha256);
      expect(first.bytes, second.bytes);
      final decoded = const SetupTabularCodec.reportExport().decodeXlsx(
        first.bytes,
      );
      expect(
        jsonDecode(
          decoded.rows.last[decoded.headers.indexOf('data_detail')],
        )['original_base_amount'],
        '0.730000',
      );
    },
  );
  test('empty export still contains attributable metadata row', () async {
    final d = exportDocument();
    d['rows'] = <Object?>[];
    d['metadata'] = {...(d['metadata'] as Map), 'row_count': 0};
    final a = await artifact(d, format: 'csv');
    final decoded = const SetupTabularCodec.reportExport().decodeCsv(a.bytes);
    expect(a.rowCount, 0);
    expect(decoded.rows.single.first, 'metadata');
    expect(decoded.rows.single, contains('report'));
  });
  test(
    'formula-like labels are neutralized without rewriting exact negatives',
    () async {
      for (final name in ['+cmd', '-2+2', '@SUM(1)', ' \t=cmd']) {
        final d = exportDocument();
        d['rows'] = [
          {'id': 'r', 'name': name, 'value': '-0.000001'},
        ];
        final a = await artifact(d, format: 'csv');
        final table = const SetupTabularCodec.reportExport().decodeCsv(a.bytes);
        expect(table.rows.last[table.headers.indexOf('data_name')], "'$name");
        expect(
          table.rows.last[table.headers.indexOf('data_value')],
          '-0.000001',
        );
      }
    },
  );
  test(
    'numeric financial JSON is rejected before any artifact is produced',
    () async {
      final d = exportDocument();
      d['rows'] = [
        {'id': 'r', 'amount': 0.1},
      ];
      await expectLater(artifact(d), throwsFormatException);
    },
  );
  test(
    'row column cell and character bounds fail without truncating',
    () async {
      final d = exportDocument();
      d['rows'] = [
        for (var i = 0; i < 10001; i++) {'id': 'r$i'},
      ];
      await expectLater(artifact(d), throwsFormatException);
      d['rows'] = [
        {for (var i = 0; i < 257; i++) 'column$i': 'value'},
      ];
      d['metadata'] = {...(d['metadata'] as Map), 'row_count': 1};
      await expectLater(artifact(d), throwsFormatException);
      for (final value in ['x' * 32768, 'bad\u0000', 'bad\uD800']) {
        d['rows'] = [
          {'id': 'r', 'name': value},
        ];
        await expectLater(artifact(d), throwsFormatException);
      }
    },
  );
  test('large but permitted row count does not bypass cell bound', () async {
    final d = exportDocument();
    d['rows'] = [
      for (var i = 0; i < 5000; i++)
        {for (var k = 0; k < 100; k++) 'column$k': 'x'},
    ];
    d['metadata'] = {...(d['metadata'] as Map), 'row_count': 5000};
    await expectLater(artifact(d), throwsFormatException);
  });
  group('scoped export gateway', () {
    const scope = TenantContext(
      tenantId: 't',
      actorId: 'actor',
      legalEntityId: 'e',
      branchId: 'b',
    );
    const selection = {
      'source_type': 'close',
      'source_id': 'report',
      'section': 'sources',
      'filters': {'component_key': 'GRNI:b'},
    };
    late SupabaseClient client;
    late SupabaseReportExportGateway gateway;
    Object? response;
    var status = 200;
    final requests = <http.Request>[];
    Future<Map<String, Object?>> previewResponse(Map<String, Object?> d) async {
      final raw = jsonEncode(d);
      return {
        'canonical_text': raw,
        'source_hash': await ReportExportCodec.hash(utf8.encode(raw)),
      };
    }

    setUp(() async {
      requests.clear();
      status = 200;
      response = await previewResponse(exportDocument());
      client = SupabaseClient(
        'https://example.test',
        'synthetic-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/token')) {
            final claims = base64Url
                .encode(
                  utf8.encode(
                    jsonEncode({
                      'sub': 'actor',
                      'role': 'authenticated',
                      'exp': 4102444800,
                    }),
                  ),
                )
                .replaceAll('=', '');
            return http.Response(
              jsonEncode({
                'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
                'refresh_token': 'synthetic',
                'expires_in': 3600,
                'token_type': 'bearer',
                'user': {
                  'id': 'actor',
                  'aud': 'authenticated',
                  'app_metadata': {},
                  'user_metadata': {},
                  'created_at': '2026-09-01T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          requests.add(r);
          return http.Response(
            jsonEncode(response),
            status,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.signInWithPassword(
        email: 'actor@example.test',
        password: 'synthetic-only',
      );
      gateway = SupabaseReportExportGateway(client);
    });
    tearDown(() => client.dispose());
    test(
      'canonical hash and exact filter identity validated on preview',
      () async {
        final doc = await gateway.preview(scope, selection);
        expect((doc['rows'] as List).single['value'], '-9007199254.740993');
        expect(
          jsonDecode(requests.single.body)['p_filters'],
          selection['filters'],
        );
      },
    );
    test(
      'tampered canonical text or wrong source actor cannot be accepted',
      () async {
        response = {...(response as Map), 'source_hash': '0' * 64};
        await expectLater(
          gateway.preview(scope, selection),
          throwsFormatException,
        );
        final doc = exportDocument();
        doc['metadata'] = {...(doc['metadata'] as Map), 'actor_id': 'other'};
        response = await previewResponse(doc);
        await expectLater(
          gateway.preview(scope, selection),
          throwsFormatException,
        );
      },
    );
    test('valid hash cannot bypass changed filter or source scope', () async {
      final doc = exportDocument();
      doc['metadata'] = {
        ...(doc['metadata'] as Map),
        'filters': {},
        'legal_entity_id': 'other',
      };
      response = await previewResponse(doc);
      await expectLater(
        gateway.preview(scope, selection),
        throwsFormatException,
      );
    });
    CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      clientTimestamp: DateTime.utc(2026, 9, 26),
      expectedEntityVersion: 0,
      payload: {
        ...selection,
        'id': 'export',
        'source_hash': 'a' * 64,
        'file_sha256': 'b' * 64,
        'file_format': 'xlsx',
        'file_name': 'report.xlsx',
        'file_size': 1000,
        'row_count': 1,
      },
    );
    Map<String, Object?> receipt() => {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {
        ...command().payload,
        'tenant_id': 't',
        'legal_entity_id': 'e',
        'branch_id': 'b',
        'actor_id': 'actor',
        'status': 'registered',
        'version': 1,
      },
    };
    test('registration verifies job file identity and current actor', () async {
      response = receipt();
      expect((await gateway.record(command()))['id'], 'export');
      response = {
        ...receipt(),
        'entity': {...(receipt()['entity'] as Map), 'file_sha256': 'c' * 64},
      };
      await expectLater(
        gateway.record(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    });
    test(
      'permission and MFA errors retain their access classification',
      () async {
        status = 403;
        response = {'code': '42501', 'message': 'RECENT_MFA_REQUIRED'};
        await expectLater(
          gateway.preview(scope, selection),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', 'MFA_REQUIRED'),
          ),
        );
        response = {'code': '42501', 'message': 'PERMISSION_DENIED'};
        await expectLater(
          gateway.record(command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'PERMISSION_DENIED',
            ),
          ),
        );
      },
    );
  });
}
