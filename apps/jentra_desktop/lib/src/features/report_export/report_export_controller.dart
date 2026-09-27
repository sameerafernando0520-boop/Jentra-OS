import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import '../../app_providers.dart';

final reportExportGatewayProvider = Provider<ReportExportGateway?>(
  (ref) => null,
);
final reportExportFilesProvider = Provider<ReportExportFiles>(
  (ref) => const NativeReportExportFiles(),
);
final reportExportControllerProvider =
    Provider.autoDispose<ReportExportController?>((ref) {
      final s = ref.watch(activeTenantContextProvider),
          g = ref.watch(reportExportGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (s == null ||
          !s.hasOperationalScope ||
          g == null ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'finance.view',
            'finance.reports.export',
          ].every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = ReportExportController(
        scope: s,
        gateway: g,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        files: ref.watch(reportExportFilesProvider),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      return c;
    });

final class ReportExportController extends ChangeNotifier {
  ReportExportController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.files,
    required this.online,
  });
  final TenantContext scope;
  final ReportExportGateway gateway;
  final QuotationDraftStore drafts;
  final ReportExportFiles files;
  static const slot = 'governed-report-export';
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  int _epoch = 0;
  Map<String, Object?> form = {}, document = {};
  QuotationLocalDraft? local;
  String? error, message;
  bool get pending => local?.pending != null;
  bool get locked =>
      busy ||
      pending ||
      denied ||
      form['status'] == 'registered' ||
      form['status'] == 'delivered';
  bool current(int epoch) => !_disposed && online && !denied && epoch == _epoch;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    if (!value) {
      _epoch++;
      verified = false;
      document = {};
    }
    emit();
  }

  void deny(Object e) {
    if (e is DomainError &&
        [
          'PERMISSION_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        ].contains(e.code)) {
      _epoch++;
      denied = true;
      verified = false;
      document = {};
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      deny(e);
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : form['status'] == 'registered'
          ? 'Export registered. Local delivery failed; retry retains the same job and exact bytes.'
          : 'Unable to complete the export. The saved request is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Map<String, Object?> selection(Map<String, Object?> p) => {
    for (final k in ['source_type', 'source_id', 'section', 'filters']) k: p[k],
  };
  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: 0);
    local = await drafts.load(scope, slot);
  }

  Future<void> initialize(Map<String, Object?> initial) => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form ?? {};
    if (!pending &&
        form['status'] != 'registered' &&
        initial['source_id'] is String) {
      form = {
        ...initial,
        'id': const Uuid().v4(),
        'file_format': 'xlsx',
        'status': 'local',
      };
      await persist();
    }
    if (online && form['source_id'] is String) await preview();
  });
  Future<void> preview() async {
    if (!online || _disposed) return;
    final epoch = _epoch;
    final r = await gateway.preview(
      scope,
      selection(local?.pending?.envelope.payload ?? form),
    );
    if (_disposed || !online || epoch != _epoch) return;
    denied = false;
    verified = true;
    document = r;
  }

  Future<void> refresh() => run(preview);
  void format(String v) {
    if (locked) return;
    form = {...form, 'file_format': v};
    emit();
  }

  Future<bool> canLeave() async {
    if (busy) return false;
    if (!denied && !pending && form.isNotEmpty) await persist();
    return true;
  }

  Future<void> newExport() => run(() async {
    if (pending || denied || form['status'] == 'registered') return;
    form = {
      ...selection(form),
      'id': const Uuid().v4(),
      'file_format': 'xlsx',
      'status': 'local',
    };
    document = {};
    verified = false;
    await persist();
    if (online) await preview();
  });
  Future<void> deliver() => run(() async {
    if (!online || denied || form['status'] == 'delivered') return;
    final epoch = _epoch;
    // Every retry obtains fresh server source and export access before encoding.
    await preview();
    if (!current(epoch) || !verified) return;
    final request = local?.pending;
    final registered = form['status'] == 'registered';
    final saved =
        request?.envelope.payload ??
        (registered
            ? (form['registration_payload'] as Map).cast<String, Object?>()
            : null);
    final exportId = saved?['id'] as String? ?? form['id'] as String;
    final format =
        saved?['file_format'] as String? ?? form['file_format'] as String;
    final prepared =
        saved?['prepared_at'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final hash = document['source_hash'] as String;
    final artifact = await const ReportExportCodec().encode(
      document,
      format: format,
      exportId: exportId,
      preparedAt: prepared,
      sourceHash: hash,
    );
    if (!current(epoch)) return;
    final fileName =
        saved?['file_name'] as String? ??
        '${form['source_type']}-$exportId.$format';
    if (saved != null &&
        (saved['source_hash'] != hash ||
            saved['file_sha256'] != artifact.sha256 ||
            saved['file_size'] != artifact.bytes.length)) {
      throw const FormatException(
        'The saved export bytes no longer match. No file was written.',
      );
    }
    final target = await files.choose(fileName);
    if (target == null || !current(epoch)) return;
    var sealed = request;
    Map<String, Object?> registeredForm;
    if (!registered) {
      if (sealed == null) {
        final payload = {
          ...selection(form),
          'id': exportId,
          'file_format': format,
          'file_name': fileName,
          'file_size': artifact.bytes.length,
          'file_sha256': artifact.sha256,
          'columns': artifact.columns,
          'row_count': artifact.rowCount,
          'source_hash': hash,
          'prepared_at': prepared,
        };
        await persist();
        sealed = await drafts.prepare(
          scope,
          slot,
          verb: 'accept',
          expectedVersion: 0,
          payload: payload,
        );
        local = await drafts.load(scope, slot);
      }
      if (!current(epoch)) return;
      try {
        final receipt = await gateway.record(sealed.envelope);
        registeredForm = {
          ...selection(sealed.envelope.payload),
          'id': exportId,
          'file_format': format,
          'status': 'registered',
          'job_id': receipt['id'],
          'registration_payload': sealed.envelope.payload,
        };
        // Persist registration before optional local delivery, even after disposal.
        await drafts.confirm(
          scope,
          slot,
          sealed.envelope.commandId,
          form: registeredForm,
          expectedVersion: 0,
        );
      } on DomainError catch (e) {
        await drafts.recordFailure(
          scope,
          slot,
          e,
          commandId: sealed.envelope.commandId,
        );
        if (!_disposed) local = await drafts.load(scope, slot);
        rethrow;
      }
    } else {
      registeredForm = form;
    }
    if (_disposed) return;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = registeredForm;
    if (!current(epoch)) return;
    await files.write(
      target,
      artifact.bytes,
      format == 'csv'
          ? 'text/csv'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final delivered = {...registeredForm, 'status': 'delivered'};
    await drafts.save(scope, slot, delivered, expectedVersion: 0);
    if (_disposed) return;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = delivered;
    if (!current(epoch)) return;
    message =
        'Export saved. Its source, scope and exact file hash are recorded.';
  });
}
