import 'document_lifecycle.dart';
import 'exact_decimal.dart';
import 'tabular_document.dart';
import 'validation.dart';

enum BusinessSetupCategory {
  finance,
  parties,
  catalogue,
  governance,
  filesAndData,
  reports,
}

enum BusinessSetupResource {
  currencies,
  exchangeRates,
  taxDefinitions,
  accounts,
  fiscalPeriods,
  parties,
  contacts,
  units,
  products,
  documentSequences,
  workflowDefinitions,
  approvalMatrixSteps,
  attachments,
  notifications,
  importJobs,
  exportJobs,
  reportDefinitions,
}

extension BusinessSetupResourceContract on BusinessSetupResource {
  String get apiView => switch (this) {
    BusinessSetupResource.currencies => 'currencies',
    BusinessSetupResource.exchangeRates => 'exchange_rates',
    BusinessSetupResource.taxDefinitions => 'tax_definitions',
    BusinessSetupResource.accounts => 'accounts',
    BusinessSetupResource.fiscalPeriods => 'fiscal_periods',
    BusinessSetupResource.parties => 'parties',
    BusinessSetupResource.contacts => 'contacts',
    BusinessSetupResource.units => 'units',
    BusinessSetupResource.products => 'products',
    BusinessSetupResource.documentSequences => 'document_sequences',
    BusinessSetupResource.workflowDefinitions => 'workflow_definitions',
    BusinessSetupResource.approvalMatrixSteps => 'approval_matrix_steps',
    BusinessSetupResource.attachments => 'attachments',
    BusinessSetupResource.notifications => 'my_notifications',
    BusinessSetupResource.importJobs => 'import_jobs',
    BusinessSetupResource.exportJobs => 'export_jobs',
    BusinessSetupResource.reportDefinitions => 'report_definitions',
  };

  String? get rpcName => switch (this) {
    BusinessSetupResource.currencies ||
    BusinessSetupResource.notifications ||
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs => null,
    BusinessSetupResource.exchangeRates => 'upsert_exchange_rate',
    BusinessSetupResource.taxDefinitions => 'upsert_tax_definition',
    BusinessSetupResource.accounts => 'upsert_account',
    BusinessSetupResource.fiscalPeriods => 'upsert_fiscal_period',
    BusinessSetupResource.parties => 'upsert_party',
    BusinessSetupResource.contacts => 'upsert_contact',
    BusinessSetupResource.units => 'upsert_unit',
    BusinessSetupResource.products => 'upsert_product',
    BusinessSetupResource.documentSequences => 'upsert_document_sequence',
    BusinessSetupResource.workflowDefinitions => 'upsert_workflow_definition',
    BusinessSetupResource.approvalMatrixSteps => 'upsert_approval_matrix_step',
    BusinessSetupResource.attachments => 'register_attachment',
    BusinessSetupResource.reportDefinitions => 'upsert_report_definition',
  };

  BusinessSetupCategory get category => switch (this) {
    BusinessSetupResource.currencies ||
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods => BusinessSetupCategory.finance,
    BusinessSetupResource.parties ||
    BusinessSetupResource.contacts => BusinessSetupCategory.parties,
    BusinessSetupResource.units ||
    BusinessSetupResource.products => BusinessSetupCategory.catalogue,
    BusinessSetupResource.documentSequences ||
    BusinessSetupResource.workflowDefinitions ||
    BusinessSetupResource.approvalMatrixSteps =>
      BusinessSetupCategory.governance,
    BusinessSetupResource.attachments ||
    BusinessSetupResource.notifications ||
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs => BusinessSetupCategory.filesAndData,
    BusinessSetupResource.reportDefinitions => BusinessSetupCategory.reports,
  };

  String get label => switch (this) {
    BusinessSetupResource.currencies => 'Currencies',
    BusinessSetupResource.exchangeRates => 'Exchange rates',
    BusinessSetupResource.taxDefinitions => 'Tax definitions',
    BusinessSetupResource.accounts => 'Chart of accounts',
    BusinessSetupResource.fiscalPeriods => 'Fiscal periods',
    BusinessSetupResource.parties => 'Parties',
    BusinessSetupResource.contacts => 'Contacts',
    BusinessSetupResource.units => 'Units of measure',
    BusinessSetupResource.products => 'Products',
    BusinessSetupResource.documentSequences => 'Document numbering',
    BusinessSetupResource.workflowDefinitions => 'Workflows',
    BusinessSetupResource.approvalMatrixSteps => 'Approval matrices',
    BusinessSetupResource.attachments => 'Attachments',
    BusinessSetupResource.notifications => 'Notifications',
    BusinessSetupResource.importJobs => 'Imports',
    BusinessSetupResource.exportJobs => 'Exports',
    BusinessSetupResource.reportDefinitions => 'Saved reports',
  };

  String get singularLabel => switch (this) {
    BusinessSetupResource.currencies => 'currency',
    BusinessSetupResource.exchangeRates => 'exchange rate',
    BusinessSetupResource.taxDefinitions => 'tax definition',
    BusinessSetupResource.accounts => 'account',
    BusinessSetupResource.fiscalPeriods => 'fiscal period',
    BusinessSetupResource.parties => 'party',
    BusinessSetupResource.contacts => 'contact',
    BusinessSetupResource.units => 'unit',
    BusinessSetupResource.products => 'product',
    BusinessSetupResource.documentSequences => 'document sequence',
    BusinessSetupResource.workflowDefinitions => 'workflow',
    BusinessSetupResource.approvalMatrixSteps => 'approval step',
    BusinessSetupResource.attachments => 'attachment',
    BusinessSetupResource.notifications => 'notification',
    BusinessSetupResource.importJobs => 'import',
    BusinessSetupResource.exportJobs => 'export',
    BusinessSetupResource.reportDefinitions => 'saved report',
  };

  String get viewPermission => switch (this) {
    BusinessSetupResource.currencies => 'core.setup.view',
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods => 'finance.setup.view',
    BusinessSetupResource.parties ||
    BusinessSetupResource.contacts => 'crm.parties.view',
    BusinessSetupResource.units ||
    BusinessSetupResource.products => 'inventory.catalog.view',
    BusinessSetupResource.documentSequences => 'core.setup.view',
    BusinessSetupResource.workflowDefinitions ||
    BusinessSetupResource.approvalMatrixSteps => 'workflow.configure',
    BusinessSetupResource.attachments ||
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs ||
    BusinessSetupResource.notifications => 'core.files.view',
    BusinessSetupResource.reportDefinitions => 'analytics.reports.view',
  };

  String get managePermission => switch (this) {
    BusinessSetupResource.currencies => 'core.setup.manage',
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods => 'finance.setup.manage',
    BusinessSetupResource.parties ||
    BusinessSetupResource.contacts => 'crm.parties.manage',
    BusinessSetupResource.units ||
    BusinessSetupResource.products => 'inventory.catalog.manage',
    BusinessSetupResource.documentSequences => 'core.setup.manage',
    BusinessSetupResource.workflowDefinitions ||
    BusinessSetupResource.approvalMatrixSteps => 'workflow.configure',
    BusinessSetupResource.attachments ||
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs ||
    BusinessSetupResource.notifications => 'core.files.manage',
    BusinessSetupResource.reportDefinitions => 'analytics.reports.manage',
  };

  bool get isReadOnly => switch (this) {
    BusinessSetupResource.currencies ||
    BusinessSetupResource.notifications ||
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs => true,
    _ => false,
  };

  bool get requiresLegalEntity => switch (this) {
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods ||
    BusinessSetupResource.products => true,
    _ => false,
  };
}

final class SetupListQuery {
  SetupListQuery({
    this.search = '',
    this.status,
    this.limit = 50,
    this.cursor,
    this.sort = const ['code', 'id'],
  }) {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Expected a value from 1 to 200',
      );
    }
  }

  final String search;
  final String? status;
  final int limit;
  final String? cursor;
  final List<String> sort;

  String get normalizedSearch => search.trim();
}

final class SetupRecord {
  SetupRecord({
    required this.resource,
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required Map<String, Object?> fields,
    this.legalEntityId,
  }) : fields = Map.unmodifiable(fields);

  factory SetupRecord.fromJson(
    BusinessSetupResource resource,
    Map<String, Object?> json,
  ) {
    const canonical = <String>{
      'id',
      'tenant_id',
      'legal_entity_id',
      'code',
      'name',
      'status',
      'version',
      'created_at',
      'updated_at',
    };
    final fields = <String, Object?>{
      for (final entry in json.entries)
        if (!canonical.contains(entry.key)) entry.key: entry.value,
    };
    return SetupRecord(
      resource: resource,
      id: json['id'].toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      legalEntityId: json['legal_entity_id']?.toString(),
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      version: _readInt(json['version'], fallback: 1),
      createdAt: _readDate(json['created_at']),
      updatedAt: _readDate(json['updated_at']),
      fields: fields,
    );
  }

  final BusinessSetupResource resource;
  final String id;
  final String tenantId;
  final String? legalEntityId;
  final String code;
  final String name;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tenant_id': tenantId,
    'legal_entity_id': legalEntityId,
    'code': code,
    'name': name,
    'status': status,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    ...fields,
  };

  static int _readInt(Object? value, {required int fallback}) =>
      switch (value) {
        int number => number,
        num number => number.toInt(),
        String text => int.tryParse(text) ?? fallback,
        _ => fallback,
      };

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

final class BusinessSetupValidator {
  const BusinessSetupValidator._();

  static ValidationResult validate(
    BusinessSetupResource resource,
    Map<String, Object?> fields,
  ) {
    final issues = <ValidationIssue>[];
    void required(String field, [String? message]) {
      final value = fields[field];
      if (value == null || value.toString().trim().isEmpty) {
        issues.add(
          ValidationIssue(
            field: field,
            message: message ?? 'This field is required.',
          ),
        );
      }
    }

    void codeAndName({String code = 'code', String name = 'name'}) {
      required(code);
      required(name);
    }

    void oneOf(String field, Set<String> allowed) {
      final value = fields[field]?.toString().trim();
      if (value != null && value.isNotEmpty && !allowed.contains(value)) {
        issues.add(
          ValidationIssue(
            field: field,
            message: 'Choose one of: ${allowed.join(', ')}.',
          ),
        );
      }
    }

    void isoCurrency(String field, {bool optional = false}) {
      final value = fields[field]?.toString().trim() ?? '';
      if (optional && value.isEmpty) return;
      if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(value)) {
        issues.add(
          ValidationIssue(
            field: field,
            message: 'Enter a three-letter ISO currency code.',
          ),
        );
      }
    }

    switch (resource) {
      case BusinessSetupResource.currencies:
        break;
      case BusinessSetupResource.exchangeRates:
        required('source_currency_code');
        required('target_currency_code');
        required('rate');
        required('effective_date');
        required('rate_type');
        required('source');
        oneOf('rate_type', const {'spot', 'average', 'closing', 'custom'});
        isoCurrency('source_currency_code');
        isoCurrency('target_currency_code');
        _validateDate(fields, issues, 'effective_date');
        final source = fields['source_currency_code']?.toString().toUpperCase();
        final target = fields['target_currency_code']?.toString().toUpperCase();
        if (source != null && source == target) {
          issues.add(
            const ValidationIssue(
              field: 'target_currency_code',
              message: 'Choose a different target currency.',
            ),
          );
        }
        final rate = _decimal(fields['rate'], scale: 10);
        if (rate == null || !rate.isPositive) {
          issues.add(
            const ValidationIssue(
              field: 'rate',
              message: 'Rate must be greater than zero.',
            ),
          );
        }
      case BusinessSetupResource.taxDefinitions:
        codeAndName();
        required('rate');
        required('kind');
        required('valid_from');
        oneOf('kind', const {
          'input',
          'output',
          'withholding',
          'zero',
          'exempt',
        });
        final rate = _decimal(fields['rate'], scale: 6);
        final hundred = ExactDecimal.parse('100', scale: 6);
        if (rate == null || rate.isNegative || rate.compareTo(hundred) > 0) {
          issues.add(
            const ValidationIssue(
              field: 'rate',
              message: 'Tax rate must be from 0 to 100.',
            ),
          );
        }
        _validateDateRange(fields, issues, 'valid_from', 'valid_to');
      case BusinessSetupResource.accounts:
        codeAndName();
        required('account_type');
        required('normal_balance');
        oneOf('account_type', const {
          'asset',
          'liability',
          'equity',
          'revenue',
          'expense',
        });
        oneOf('normal_balance', const {'debit', 'credit'});
        isoCurrency('currency_code', optional: true);
        if (fields['id'] != null && fields['id'] == fields['parent_id']) {
          issues.add(
            const ValidationIssue(
              field: 'parent_id',
              message: 'An account cannot be its own parent.',
            ),
          );
        }
      case BusinessSetupResource.fiscalPeriods:
        required('name');
        required('start_date');
        required('end_date');
        required('state');
        oneOf('state', const {'open', 'soft_locked', 'hard_locked'});
        _validateDateRange(fields, issues, 'start_date', 'end_date');
      case BusinessSetupResource.parties:
        required('code');
        required('legal_name');
        required('display_name');
        required('kind');
        oneOf('kind', const {'customer', 'supplier', 'both'});
        final creditLimit = _decimal(fields['credit_limit'], scale: 6);
        if (fields['credit_limit'] != null &&
            (creditLimit == null || creditLimit.isNegative)) {
          issues.add(
            const ValidationIssue(
              field: 'credit_limit',
              message: 'Credit limit must be zero or greater.',
            ),
          );
        }
        isoCurrency('credit_currency_code', optional: true);
        final paymentTerms = _integer(fields['payment_terms_days']);
        if (fields['payment_terms_days'] != null &&
            (paymentTerms == null || paymentTerms < 0 || paymentTerms > 3650)) {
          issues.add(
            const ValidationIssue(
              field: 'payment_terms_days',
              message: 'Payment terms must be from 0 to 3650 days.',
            ),
          );
        }
        final countryCode = fields['country_code']?.toString().trim() ?? '';
        if (countryCode.isNotEmpty &&
            !RegExp(r'^[A-Za-z]{2}$').hasMatch(countryCode)) {
          issues.add(
            const ValidationIssue(
              field: 'country_code',
              message: 'Enter a two-letter country code.',
            ),
          );
        }
      case BusinessSetupResource.contacts:
        required('party_id');
        required('name');
      case BusinessSetupResource.units:
        codeAndName();
        required('symbol');
        required('category');
        oneOf('category', const {
          'quantity',
          'weight',
          'length',
          'area',
          'volume',
          'time',
          'service',
        });
        final precision = _integer(fields['precision']);
        if (precision == null || precision < 0 || precision > 6) {
          issues.add(
            const ValidationIssue(
              field: 'precision',
              message: 'Precision must be from 0 to 6.',
            ),
          );
        }
      case BusinessSetupResource.products:
        codeAndName(code: 'sku');
        required('kind');
        required('base_unit_id');
        required('tracking_mode');
        oneOf('kind', const {'stocked', 'non_stocked', 'service'});
        oneOf('tracking_mode', const {'none', 'lot', 'serial'});
      case BusinessSetupResource.documentSequences:
        required('document_type');
        required('reset_policy');
        oneOf('reset_policy', const {'never', 'yearly', 'monthly'});
        final padding = _integer(fields['padding']);
        if (padding == null || padding < 1 || padding > 12) {
          issues.add(
            const ValidationIssue(
              field: 'padding',
              message: 'Padding must be from 1 to 12.',
            ),
          );
        }
        final nextValue = _integer(fields['next_value']);
        if (fields['next_value'] != null &&
            (nextValue == null || nextValue < 1)) {
          issues.add(
            const ValidationIssue(
              field: 'next_value',
              message: 'Next number must be greater than zero.',
            ),
          );
        }
      case BusinessSetupResource.workflowDefinitions:
        required('document_type');
        required('name');
        required('lifecycle');
        final revision = _integer(fields['revision']);
        if (fields['revision'] != null && (revision == null || revision < 1)) {
          issues.add(
            const ValidationIssue(
              field: 'revision',
              message: 'Revision must be greater than zero.',
            ),
          );
        }
        final lifecycle = fields['lifecycle'];
        final states = lifecycle is Map ? lifecycle['states'] : null;
        final transitions = lifecycle is Map ? lifecycle['transitions'] : null;
        final requiredStates = DocumentStatus.values
            .map((status) => status.name)
            .toSet();
        var transitionsValid = transitions is List && transitions.isNotEmpty;
        if (transitions is List) {
          for (final transition in transitions) {
            if (transition is! List || transition.length != 2) {
              transitionsValid = false;
              continue;
            }
            final fromName = transition[0].toString();
            final toName = transition[1].toString();
            final from = DocumentStatus.values
                .where((status) => status.name == fromName)
                .firstOrNull;
            final to = DocumentStatus.values
                .where((status) => status.name == toName)
                .firstOrNull;
            if (from == null ||
                to == null ||
                !DocumentLifecycle.canTransition(from, to)) {
              transitionsValid = false;
            }
          }
        }
        if (states is! List ||
            !transitionsValid ||
            !states
                .map((value) => value.toString())
                .toSet()
                .containsAll(requiredStates)) {
          issues.add(
            const ValidationIssue(
              field: 'lifecycle',
              message:
                  'Lifecycle must define the canonical states and transitions.',
            ),
          );
        }
      case BusinessSetupResource.approvalMatrixSteps:
        required('workflow_definition_id');
        required('role_id');
        required('step_order');
        final stepOrder = _integer(fields['step_order']);
        if (fields['step_order'] != null &&
            (stepOrder == null || stepOrder < 1 || stepOrder > 100)) {
          issues.add(
            const ValidationIssue(
              field: 'step_order',
              message: 'Step order must be from 1 to 100.',
            ),
          );
        }
        final minimum = _decimal(fields['minimum_amount'], scale: 6);
        final maximum = _decimal(fields['maximum_amount'], scale: 6);
        if (minimum != null &&
            maximum != null &&
            minimum.compareTo(maximum) > 0) {
          issues.add(
            const ValidationIssue(
              field: 'maximum_amount',
              message: 'Maximum must not be below minimum.',
            ),
          );
        }
        isoCurrency(
          'currency_code',
          optional: minimum == null && maximum == null,
        );
      case BusinessSetupResource.attachments:
        required('aggregate_type');
        required('aggregate_id');
        required('file_name');
        required('mime_type');
        required('byte_size');
      case BusinessSetupResource.reportDefinitions:
        required('code');
        required('title');
        required('source_view');
        required('columns');
        final columns = fields['columns'];
        if (columns != null && (columns is! List || columns.isEmpty)) {
          issues.add(
            const ValidationIssue(
              field: 'columns',
              message: 'Choose at least one report column.',
            ),
          );
        }
        final filters = fields['filters'];
        if (filters != null && filters is! Map) {
          issues.add(
            const ValidationIssue(
              field: 'filters',
              message: 'Filters must be a JSON object.',
            ),
          );
        }
        final sort = fields['sort'];
        if (sort != null && sort is! List) {
          issues.add(
            const ValidationIssue(
              field: 'sort',
              message: 'Sort must be a list of fields.',
            ),
          );
        }
        final rowLimit = _integer(fields['row_limit']);
        if (fields['row_limit'] != null &&
            (rowLimit == null || rowLimit < 1 || rowLimit > 200)) {
          issues.add(
            const ValidationIssue(
              field: 'row_limit',
              message: 'Row limit must be from 1 to 200.',
            ),
          );
        }
      case BusinessSetupResource.notifications ||
          BusinessSetupResource.importJobs ||
          BusinessSetupResource.exportJobs:
        break;
    }

    if (!resource.isReadOnly) {
      final status = fields['status']?.toString();
      if (status != null &&
          status != 'active' &&
          status != 'inactive' &&
          !(resource == BusinessSetupResource.workflowDefinitions &&
              status == 'draft')) {
        issues.add(
          const ValidationIssue(
            field: 'status',
            message: 'Status is not supported.',
          ),
        );
      }
    }
    return ValidationResult(issues);
  }

  static ExactDecimal? _decimal(Object? value, {required int scale}) {
    if (value == null || value.toString().trim().isEmpty) return null;
    try {
      return ExactDecimal.parse(value.toString(), scale: scale);
    } on FormatException {
      return null;
    }
  }

  static int? _integer(Object? value) => switch (value) {
    int number => number,
    num number when number.isFinite && number == number.truncate() =>
      number.toInt(),
    num _ => null,
    _ => int.tryParse(value?.toString() ?? ''),
  };

  static void _validateDateRange(
    Map<String, Object?> fields,
    List<ValidationIssue> issues,
    String fromField,
    String toField,
  ) {
    final from = _validateDate(fields, issues, fromField);
    final toText = fields[toField]?.toString() ?? '';
    final to = toText.isEmpty ? null : DateTime.tryParse(toText);
    if (from != null &&
        toText.isNotEmpty &&
        (to == null || to.isBefore(from))) {
      issues.add(
        ValidationIssue(
          field: toField,
          message: 'End date must not be before start date.',
        ),
      );
    }
  }

  static DateTime? _validateDate(
    Map<String, Object?> fields,
    List<ValidationIssue> issues,
    String field,
  ) {
    final text = fields[field]?.toString() ?? '';
    final value = DateTime.tryParse(text);
    if (text.isNotEmpty && value == null) {
      issues.add(ValidationIssue(field: field, message: 'Enter a valid date.'));
    }
    return value;
  }
}

final class SetupImportIssue {
  const SetupImportIssue({
    required this.row,
    required this.field,
    required this.message,
  });

  final int row;
  final String field;
  final String message;
}

/// Client-side field preview. Server authorization and relational checks still
/// run atomically when the user explicitly applies the import.
final class SetupImportPreview {
  SetupImportPreview._({
    required this.rowCount,
    required List<SetupImportIssue> issues,
  }) : issues = List.unmodifiable(issues);

  factory SetupImportPreview.validate(
    BusinessSetupResource resource,
    TabularDocument document,
  ) {
    final issues = <SetupImportIssue>[];
    final rows = document.toRowMaps();
    for (var index = 0; index < rows.length; index += 1) {
      final validation = BusinessSetupValidator.validate(resource, rows[index]);
      for (final issue in validation.issues) {
        issues.add(
          SetupImportIssue(
            row: index + 2,
            field: issue.field,
            message: issue.message,
          ),
        );
      }
    }
    return SetupImportPreview._(rowCount: rows.length, issues: issues);
  }

  final int rowCount;
  final List<SetupImportIssue> issues;

  bool get isValid => rowCount > 0 && issues.isEmpty;
  int get invalidRowCount => issues.map((issue) => issue.row).toSet().length;
}
