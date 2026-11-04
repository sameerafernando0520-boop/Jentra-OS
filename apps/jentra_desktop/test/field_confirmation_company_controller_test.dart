import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/field_confirmation_company.dart';
import 'package:jentra_desktop/src/features/sales/field_confirmation_company_controller.dart';

const companyScope = FieldSalesScope('tenant', 'company', 'branch');
final approvedRequest = <String, dynamic>{
  'id': 'request',
  'version': '2',
  'customer_id': 'customer',
  'customer_name': 'Authorized Customer',
  'company_state': 'approved',
  'customer_state': 'email_link_pending',
  'source_digest': 'a' * 64,
  'preview': {
    'currency_code': 'LKR',
    'pricing': {
      'subtotal': '1250.000000',
      'discount_total': '0.000000',
      'tax_total': '0.000000',
      'grand_total': '1250.000000',
      'lines': [
        {
          'description': 'Governed product',
          'quantity': '1.000000',
          'unit_price': '1250.000000',
          'line_discount_amount': '0.000000',
          'header_discount_amount': '0.000000',
          'tax_amount': '0.000000',
          'tax_rate': '0.000000',
          'tax_inclusive': false,
          'line_total': '1250.000000',
        },
      ],
    },
    'terms': {
      'ship_to': {
        'address': {'line1': 'Company approved address'},
        'postcode': 12345,
      },
      'requested_date': '2026-11-03',
      'payment_terms_days': '30',
      'delivery_terms': 'Company delivery',
    },
  },
};
final authorizedContact = <String, dynamic>{
  'id': 'contact',
  'version': '9',
  'name': 'Authorized Buyer',
  'email': 'buyer@example.invalid',
  'authority_note': 'Company reviewed',
  'valid_until': '2026-12-01T00:00:00Z',
  'active': true,
};
final postedDelivery = <String, dynamic>{
  'id': 'delivery',
  'delivery_id': 'delivery',
  'version': '9007199254740993',
  'delivery_version': '9007199254740993',
  'delivery_digest': 'e' * 64,
  'customer_id': 'customer',
  'customer_name': 'Authorized Customer',
  'company_state': 'posted',
  'customer_state': 'accepted',
  'delivery_state': 'not_requested',
  'offer': {
    'document_number': 'DL-SYNTHETIC',
    'lines': [
      {
        'id': 'line',
        'description': 'Synthetic posted item',
        'posted_base_quantity': '0.500000',
        'base_unit': 'ea',
      },
    ],
  },
};

class CompanyKeys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class FakeConfirmationCompanyGateway
    implements FieldConfirmationCompanyGateway {
  @override
  String? actorId = 'manager';
  String provider = 'unavailable';
  bool fail = false;
  String? rejectCode;
  bool paged = false;
  Completer<FieldConfirmationPage>? delayedSubjects;
  final commands = <FieldSalesJson>[];
  FieldSalesJson? committed;
  FieldSalesJson? subject;
  @override
  Future<FieldConfirmationPage> subjects(FieldSalesScope s, {String? after}) =>
      delayedSubjects?.future ??
      Future.value(
        FieldConfirmationPage(
          List.of([
            after == null
                ? subject ?? approvedRequest
                : {...approvedRequest, 'id': 'request2'},
          ], growable: false),
          paged && after == null ? 'next' : null,
          providerState: provider,
        ),
      );
  @override
  Future<FieldConfirmationPage> contacts(
    FieldSalesScope s,
    String customer, {
    String? after,
  }) async => FieldConfirmationPage(
    List.of([
      after == null
          ? authorizedContact
          : {...authorizedContact, 'id': 'contact2'},
    ], growable: false),
    paged && after == null ? 'next' : null,
    providerState: provider,
  );
  @override
  Future<FieldConfirmationPage> challenges(
    FieldSalesScope s,
    String request, {
    String? after,
  }) async => FieldConfirmationPage(
    List.of(
      paged
          ? [
              {'id': after == null ? 'challenge' : 'challenge2'},
            ]
          : [],
      growable: false,
    ),
    paged && after == null ? 'next' : null,
  );
  @override
  Future<FieldSalesJson> receipt(FieldSalesScope s, String key) async =>
      committed == null
      ? {'state': 'not_found'}
      : {'state': 'committed', 'receipt': committed};
  @override
  Future<FieldSalesJson> command(FieldSalesJson p) async {
    commands.add(p);
    if (rejectCode != null) {
      throw FieldSalesFailure(
        rejectCode!,
        'Company rejected the current source.',
      );
    }
    final input = p['p_payload'] as Map;
    final entity = <String, dynamic>{
      ...sizedScope(p),
      ...input,
      'version': p['p_expected_entity_version'] == null
          ? '1'
          : (BigInt.parse(p['p_expected_entity_version'] as String) +
                    BigInt.one)
                .toString(),
      if (const {'issue_order', 'issue_delivery'}.contains(p['p_action']))
        'state': 'queued_link',
      if (const {'revoke_challenge', 'revoke_delivery'}.contains(p['p_action']))
        'state': 'revoked',
      if (p['p_action'] == 'authorize_contact') ...{
        'authorized_by': 'manager',
        'active': true,
        'channel_state': 'unverified',
      },
      if (p['p_action'] == 'revoke_contact') 'active': false,
    };
    committed = {'command_id': p['p_command_id'], 'entity': entity};
    if (fail) {
      throw const FieldSalesFailure('OUTCOME_UNKNOWN', 'Response interrupted.');
    }
    return committed!;
  }

  Map<String, dynamic> sizedScope(FieldSalesJson p) => {
    'tenant_id': p['p_tenant_id'],
    'legal_entity_id': p['p_legal_entity_id'],
    'branch_id': p['p_branch_id'],
  };
}

void main() {
  late JentraLocalDatabase db;
  late EncryptedDraftRepository repo;
  late FakeConfirmationCompanyGateway gateway;
  late FieldConfirmationCompanyController c;
  var authorized = true;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repo = EncryptedDraftRepository(db, DraftCipher(keyStore: CompanyKeys()));
    gateway = FakeConfirmationCompanyGateway();
    authorized = true;
    c = FieldConfirmationCompanyController(
      actor: 'manager',
      scope: companyScope,
      gateway: gateway,
      store: FieldConfirmationCompanyStore(repo),
      isAuthorized: () => authorized,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test('delivery requests bind posted quantities independently of accepted order terms', () async {
    gateway.provider = 'configured';
    gateway.subject = postedDelivery;
    final delivery = FieldConfirmationCompanyController(
      actor: 'manager',
      scope: companyScope,
      gateway: gateway,
      store: FieldConfirmationCompanyStore(repo, delivery: true),
      isAuthorized: () => authorized,
      delivery: true,
    );
    addTearDown(delivery.dispose);
    await delivery.open();
    await delivery.select(postedDelivery);
    expect(delivery.canIssue, isTrue);
    await delivery.issue(authorizedContact);
    expect(gateway.commands.single['p_action'], 'issue_delivery');
    expect(
      gateway.commands.single['p_payload']['delivery_version'],
      '9007199254740993',
    );
    expect(
      gateway.commands.single['p_payload'].containsKey('request_version'),
      isFalse,
    );
    expect(delivery.pending, isNull);
  });
  test('a recorded delivery exception cannot be silently replaced by another request', () async {
    gateway.provider = 'configured';
    final delivery = FieldConfirmationCompanyController(
      actor: 'manager',
      scope: companyScope,
      gateway: gateway,
      store: FieldConfirmationCompanyStore(repo, delivery: true),
      isAuthorized: () => authorized,
      delivery: true,
    );
    addTearDown(delivery.dispose);
    await delivery.open();
    await delivery.select({...postedDelivery, 'delivery_state': 'exception'});
    expect(delivery.canIssue, isFalse);
    await delivery.issue(authorizedContact);
    expect(gateway.commands, isEmpty);
  });
  test('provider unavailable permits contact administration but never issues a request', () async {
    await c.open();
    await c.select(approvedRequest);
    expect(c.canIssue, isFalse);
    await c.issue(authorizedContact);
    expect(gateway.commands, isEmpty);
    await c.authorizeContact({
      'name': 'Buyer',
      'email': 'buyer@example.invalid',
      'authority_note': 'Reviewed company authority',
      'valid_until': '2026-12-01T00:00:00Z',
    });
    expect(gateway.commands.single['p_action'], 'authorize_contact');
    expect(c.pending, isNull);
  });
  test('lost issuance response survives reopening and checks its original receipt without resending', () async {
    gateway.provider = 'configured';
    gateway.fail = true;
    await c.open();
    await c.select(approvedRequest);
    await c.issue(authorizedContact);
    expect(c.pending, isNotNull);
    expect(gateway.commands, hasLength(1));
    final original = c.pending!;
    final reopened = FieldConfirmationCompanyController(
      actor: 'manager',
      scope: companyScope,
      gateway: gateway,
      store: FieldConfirmationCompanyStore(repo),
      isAuthorized: () => authorized,
    );
    addTearDown(reopened.dispose);
    await reopened.open();
    expect(reopened.pending!.params, original.params);
    expect(gateway.commands, hasLength(1));
    await reopened.recover();
    expect(reopened.pending, isNull);
    expect(gateway.commands, hasLength(1));
  });
  test(
    'explicit original retry preserves identity when no receipt exists',
    () async {
      gateway.provider = 'configured';
      gateway.fail = true;
      await c.open();
      await c.select(approvedRequest);
      await c.issue(authorizedContact);
      final original = gateway.commands.single;
      gateway.committed = null;
      gateway.fail = false;
      await c.recover();
      expect(gateway.commands, hasLength(1));
      await c.recover(retry: true);
      expect(gateway.commands, hasLength(2));
      expect(gateway.commands.last, original);
      expect(c.pending, isNull);
    },
  );
  test('definite stale contact rejection releases the request for a fresh online review', () async {
    gateway.provider = 'configured';
    gateway.rejectCode = '40001';
    await c.open();
    await c.select(approvedRequest);
    await c.issue(authorizedContact);
    expect(c.pending, isNull);
    expect(c.error, isNotNull);
    expect(
      await FieldConfirmationCompanyStore(repo).load('manager', companyScope),
      isNull,
    );
  });
  test('access loss discards a late company page and cannot revive cached contacts', () async {
    gateway.delayedSubjects = Completer();
    final operation = c.open();
    authorized = false;
    c.lock();
    gateway.delayedSubjects!.complete(
      FieldConfirmationPage(
        [approvedRequest],
        null,
        providerState: 'configured',
      ),
    );
    await operation;
    expect(c.locked, isTrue);
    expect(c.subjects, isEmpty);
    authorized = true;
    await c.open();
    expect(c.subjects, isEmpty);
    expect(gateway.commands, isEmpty);
  });
  test('storage failure prevents any outgoing company action', () async {
    gateway.provider = 'configured';
    await c.open();
    await c.select(approvedRequest);
    await db.close();
    await c.issue(authorizedContact);
    expect(gateway.commands, isEmpty);
    expect(c.pending, isNull);
  });
  test('real gateway fixed-length pages append for requests contacts and challenges', () async {
    gateway.paged = true;
    await c.open();
    await c.moreSubjects();
    expect(c.subjects, hasLength(2));
    expect(c.error, isNull);
    await c.select(approvedRequest);
    await c.moreContacts();
    await c.moreChallenges();
    expect(c.contacts, hasLength(2));
    expect(c.challenges, hasLength(2));
    expect(c.error, isNull);
  });
  test(
    'current acceptance requires explicit revocation before a new request',
    () async {
      gateway.provider = 'configured';
      await c.open();
      await c.select({...approvedRequest, 'customer_state': 'accepted'});
      expect(c.canIssue, isFalse);
      await c.issue(authorizedContact);
      expect(gateway.commands, isEmpty);
    },
  );
}
