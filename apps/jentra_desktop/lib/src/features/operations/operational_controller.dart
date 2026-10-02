import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'operational_file_gateway.dart';
import 'operational_read_access.dart';
import '../shared/report_wait.dart';

typedef OperationalTarget = ({
  String tenantId,
  String entityId,
  String branchId,
  String kind,
  String? id,
});
final operationalGatewayProvider = Provider<OperationalGateway?>((ref) => null);
const operationalPermissions = <String, String>{
  'lead': 'crm.leads.view',
  'opportunity': 'crm.opportunities.view',
  'quotation': 'sales.quotations.view',
  'sales_order': 'sales.orders.view',
  'delivery': 'sales.deliveries.view',
  'sales_invoice': 'sales.invoices.view',
  'customer_receipt': 'finance.receipts.view',
  'sales_return': 'sales.returns.view',
  'purchase_requisition': 'procurement.requisitions.manage',
  'rfq': 'procurement.rfq.manage',
  'purchase_order': 'procurement.orders.view',
  'goods_receipt': 'procurement.receipts.post',
  'supplier_bill': 'procurement.bills.view',
  'payment_proposal': 'finance.payments.manage',
  'supplier_payment': 'finance.payments.manage',
  'purchase_return': 'procurement.returns.post',
  'inventory_transfer': 'inventory.stock.view',
  'stock_count': 'inventory.adjustments.post',
  'inventory_value_adjustment': 'inventory.valuation.post',
  'landed_extension': 'inventory.valuation.post',
  'inventory_disposition': 'inventory.dispositions.post',
  'manual_journal': 'finance.view',
  'budget': 'finance.view',
  'bank_statement': 'finance.view',
  'bank_match': 'finance.view',
};
const operationalCostKinds = {
  'delivery',
  'sales_return',
  'goods_receipt',
  'purchase_return',
  'inventory_transfer',
  'stock_count',
  'inventory_value_adjustment',
  'landed_extension',
  'inventory_disposition',
};
bool canReadOperational(String kind, Set<String> capabilities) =>
    capabilities.contains(operationalPermissions[kind]) &&
    (!operationalCostKinds.contains(kind) ||
        const {
          'inventory.stock.view',
          'inventory.cost.view',
        }.every(capabilities.contains));

final operationalControllerProvider = Provider.autoDispose
    .family<OperationalController?, OperationalTarget>((ref, target) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(operationalGatewayProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !canReadOperational(target.kind, caps.value ?? {})) {
        return null;
      }
      final c = OperationalController(
        scope: scope,
        gateway: gateway,
        target: target,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        files: switch (ref.watch(businessSetupGatewayProvider)) {
          final gateway? => BusinessSetupOperationalFileGateway(gateway),
          _ => null,
        },
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, value) => c.setOnline(value.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class OperationalController extends ChangeNotifier
    implements OperationalReadAccess {
  OperationalController({
    required this.scope,
    required this.gateway,
    required this.target,
    required this.online,
    this.drafts,
    this.files,
  });
  final TenantContext scope;
  final OperationalGateway gateway;
  final OperationalTarget target;
  final QuotationDraftStore? drafts;
  final OperationalFileGateway? files;
  QuotationLocalDraft? reportLocal;
  QuotationLocalDraft? fileLocal;
  QuotationLocalDraft? rejectionLocal;
  Map<String, Object?> reportSummary = {};
  String get reportSlot => 'operational-report-${target.kind}';
  String get viewSlot => 'operational-view-${target.kind}';
  String get fileSlot => 'operational-file-${target.kind}-${target.id}';
  String get rejectionSlot => 'operational-reject-${target.kind}-${target.id}';
  bool get reportPending => reportLocal?.pending != null;
  bool get filePending => fileLocal != null;
  bool get rejectionPending => rejectionLocal?.pending != null;
  String? get filePhase => fileLocal?.form['phase'] as String?;
  bool online, busy = false, verified = false, _disposed = false;
  int _epoch = 0;
  final reportWait = ReportWaitState();
  void cancelReportWait() {
    if (!reportWait.cancel()) return;
    _epoch++;
    clear();
    emit();
  }

  String? error, cursor, nextCursor;
  List<String?> previousPages = [];
  Map<String, Object?> filters = {}, evidence = {};
  List<Map<String, Object?>> rows = [];
  bool get matchingScope =>
      scope.tenantId == target.tenantId &&
      scope.legalEntityId == target.entityId &&
      scope.branchId == target.branchId &&
      operationalPermissions.containsKey(target.kind);
  bool current(int epoch) => !_disposed && online && _epoch == epoch;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) => current(epoch) && matchingScope && verified;
  @override
  void denyReadAccess() {
    if (_disposed) return;
    _epoch++;
    busy = false;
    clear();
    error = 'This document is unavailable with your current access.';
    emit();
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  void clear() {
    verified = false;
    evidence = {};
    rows = [];
    nextCursor = null;
    reportSummary = {};
  }

  void setOnline(bool value) {
    if (value == online) return;
    online = value;
    if (!value) {
      _epoch++;
      busy = false;
      clear();
      previousPages = [];
      cursor = null;
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clear();
    notifyListeners();
    super.dispose();
  }

  Future<void> read(String? after, List<String?> previous) async {
    if (_disposed || busy) return;
    clear();
    error = null;
    if (!matchingScope || !online) {
      error = !matchingScope
          ? 'This document is unavailable in the selected business scope.'
          : 'Connect to verify document access.';
      emit();
      return;
    }
    final epoch = ++_epoch;
    busy = true;
    emit();
    try {
      final result = target.id == null
          ? await gateway.currentPage(
              scope,
              target.kind,
              filters: filters,
              after: after,
            )
          : await gateway.evidence(
              scope,
              target.kind,
              target.id!,
              after: after,
            );
      Map<String, Object?> savedSummary = {};
      final reportId = reportLocal?.form['report_id'];
      if (current(epoch) && target.id == null && reportId is String) {
        final saved = await gateway.reportPage(scope, reportId, 'rows');
        savedSummary = (saved['summary'] as Map).cast<String, Object?>();
      }
      if (!current(epoch)) return;
      reportSummary = savedSummary;
      evidence = result;
      rows = (result['items'] as List)
          .map((v) => (v as Map).cast<String, Object?>())
          .toList();
      nextCursor = result['next_cursor'] as String?;
      cursor = after;
      previousPages = previous;
      verified = true;
    } catch (e) {
      if (!current(epoch)) return;
      clear();
      previousPages = [];
      cursor = null;
      error = e is DomainError && e.code == 'PERMISSION_DENIED'
          ? 'This document is unavailable with your current access.'
          : e is FormatException
          ? e.message
          : 'Document evidence could not be verified. Refresh to try again.';
    } finally {
      if (current(epoch)) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> refresh() => read(null, []);
  Future<void> initialize() async {
    try {
      final view = await drafts?.load(scope, viewSlot);
      if (_disposed) return;
      if (view != null) {
        final restored = view.form['filters'];
        if (restored is Map) {
          final candidate = restored.cast<String, Object?>();
          _validateFilters(candidate);
          filters = Map.of(candidate);
        }
      }
      if (target.id == null) {
        reportLocal = await drafts?.load(scope, reportSlot);
      }
      if (target.id != null) {
        fileLocal = await drafts?.load(scope, fileSlot);
        rejectionLocal = await drafts?.load(scope, rejectionSlot);
      }
      if (_disposed) return;
      await refresh();
    } catch (_) {
      if (_disposed) return;
      error = 'The encrypted report request could not be restored. No new request was sent.';
      emit();
    }
  }

  Future<void> freezeCurrentList() async {
    final store = drafts;
    if (_disposed ||
        busy ||
        !online ||
        !verified ||
        store == null ||
        target.id != null) {
      return;
    }
    reportWait.begin();
    busy = true;
    error = null;
    emit();
    final epoch = _epoch;
    try {
      var pending = reportLocal?.pending;
      if (pending == null) {
        final payload = <String, Object?>{
          'id': const Uuid().v4(),
          'kind': 'current_list',
          'document_kind': target.kind,
          'filters': Map<String, Object?>.of(filters),
          'as_of': DateTime.now().toUtc().toIso8601String().substring(0, 10),
        };
        await store.save(scope, reportSlot, payload, expectedVersion: 0);
        pending = await store.prepare(
          scope,
          reportSlot,
          verb: 'accept',
          expectedVersion: 0,
          payload: payload,
        );
        reportLocal = await store.load(scope, reportSlot);
      }
      if (!current(epoch)) return;
      reportWait.generating();
      emit();
      if (reportWait.cancelled || !current(epoch)) return;
      final result = await gateway.generate(pending.envelope);
      final confirmed = {
        ...pending.envelope.payload,
        'status': 'generated',
        'report_id': result['id'],
      };
      await store.confirm(
        scope,
        reportSlot,
        pending.envelope.commandId,
        form: confirmed,
        expectedVersion: 0,
      );
      if (_disposed) return;
      reportLocal = await store.load(scope, reportSlot);
      if (!current(epoch)) return;
      reportWait.reading();
      emit();
      final saved = await gateway.reportPage(
        scope,
        result['id'] as String,
        'rows',
      );
      if (!current(epoch)) return;
      reportSummary = (saved['summary'] as Map).cast<String, Object?>();
    } on DomainError catch (e) {
      final command = reportLocal?.pending;
      if (command != null) {
        await store.recordFailure(
          scope,
          reportSlot,
          e,
          commandId: command.envelope.commandId,
        );
      }
      if (_disposed) return;
      reportLocal = await store.load(scope, reportSlot);
      if (!current(epoch)) return;
      if (const {
        'PERMISSION_DENIED',
        'MFA_REQUIRED',
        'AUTHENTICATION_REQUIRED',
      }.contains(e.code)) {
        clear();
      }
      error = e.message;
    } catch (_) {
      if (current(epoch)) error = 'The report outcome could not be confirmed. Retry the saved request or refresh its confirmed evidence.';
    } finally {
      if (_epoch == epoch || reportWait.cancelled && _epoch == epoch + 1) {
        reportWait.finish();
        if (!_disposed) {
          busy = false;
          emit();
        }
      }
    }
  }

  Future<void> filter(Map<String, Object?> value) async {
    if (_disposed || busy || reportPending) return;
    try {
      final candidate = Map<String, Object?>.of(value)
        ..removeWhere((_, v) => v == null || v == '');
      _validateFilters(candidate);
      await drafts?.save(scope, viewSlot, {'filters': candidate});
      if (_disposed) return;
      filters = candidate;
    } on FormatException catch (failure) {
      error = failure.message;
      emit();
      return;
    } catch (_) {
      error = 'The encrypted view could not be saved. The prior filter remains active.';
      emit();
      return;
    }
    await refresh();
  }

  Future<void> addFile(SelectedAttachmentFile? selected) async {
    final store = drafts;
    final fileGateway = files;
    if (_disposed ||
        busy ||
        !online ||
        !verified ||
        target.id == null ||
        store == null ||
        fileGateway == null) {
      return;
    }
    busy = true;
    error = null;
    final epoch = _epoch;
    emit();
    var complete = false;
    try {
      var local = fileLocal;
      if (local == null) {
        if (selected == null) {
          throw const FormatException('Choose a file first.');
        }
        final check = AttachmentFilePolicy.validate(
          fileName: selected.name,
          mimeType: selected.mimeType,
          byteSize: selected.bytes.length,
        );
        if (!check.isValid) throw FormatException(check.issues.first.message);
        final digest = await Sha256().hash(selected.bytes);
        final checksum = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        final metadata = <String, Object?>{
          'aggregate_type': target.kind,
          'aggregate_id': target.id,
          'file_name': selected.name,
          'mime_type': selected.mimeType,
          'byte_size': selected.bytes.length,
        };
        await store.save(scope, fileSlot, {
          'phase': 'register',
          'metadata': metadata,
          'sha256': checksum,
        }, expectedVersion: 0);
        local = await store.load(scope, fileSlot);
        fileLocal = local;
      }
      if (!_currentFile(epoch) || local == null) return;
      final phase = local.form['phase'];
      final metadata = (local.form['metadata'] as Map).cast<String, Object?>();
      final checksum = local.form['sha256'] as String;
      if (metadata['aggregate_type'] != target.kind ||
          metadata['aggregate_id'] != target.id) {
        throw const FormatException('Saved file belongs to another document.');
      }
      if (phase == 'register' || phase == 'upload') {
        if (selected == null) {
          throw const FormatException(
            'Reselect the same file to continue upload.',
          );
        }
        final digest = await Sha256().hash(selected.bytes);
        final chosen = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (chosen != checksum ||
            selected.name != metadata['file_name'] ||
            selected.mimeType != metadata['mime_type'] ||
            selected.bytes.length != metadata['byte_size']) {
          throw const FormatException(
            'Choose the original file for this saved upload.',
          );
        }
      }
      if (phase == 'register') {
        final pending =
            local.pending ??
            await store.prepare(
              scope,
              fileSlot,
              verb: 'accept',
              payload: metadata,
              expectedVersion: 0,
            );
        local = await store.load(scope, fileSlot);
        fileLocal = local;
        if (!_currentFile(epoch)) return;
        final staged = await fileGateway.register(
          scope,
          metadata,
          pending.envelope.idempotencyKey,
        );
        if (staged.tenantId != scope.tenantId ||
            staged.fields['aggregate_type'] != target.kind ||
            staged.fields['aggregate_id'] != target.id ||
            staged.fields['upload_status'] != 'staged') {
          throw const FormatException('Registered file identity mismatch.');
        }
        await store.confirm(
          scope,
          fileSlot,
          pending.envelope.commandId,
          form: {...local!.form, 'phase': 'upload', 'staged': staged.toJson()},
          expectedVersion: 0,
        );
        if (_disposed) return;
        local = await store.load(scope, fileSlot);
        fileLocal = local;
      }
      if (!_currentFile(epoch) || local == null) return;
      if (local.form['phase'] == 'upload') {
        final staged = SetupRecord.fromJson(
          BusinessSetupResource.attachments,
          (local.form['staged'] as Map).cast<String, Object?>(),
        );
        await fileGateway.upload(staged, selected!.bytes);
        await store.save(scope, fileSlot, {
          ...local.form,
          'phase': 'complete',
        }, expectedVersion: 0);
        local = await store.load(scope, fileSlot);
        fileLocal = local;
      }
      if (!_currentFile(epoch) || local == null) return;
      if (local.form['phase'] == 'complete') {
        final staged = SetupRecord.fromJson(
          BusinessSetupResource.attachments,
          (local.form['staged'] as Map).cast<String, Object?>(),
        );
        final payload = <String, Object?>{
          'id': staged.id,
          'checksum_sha256': checksum,
          'version': staged.version,
        };
        final pending =
            local.pending ??
            await store.prepare(
              scope,
              fileSlot,
              verb: 'accept',
              payload: payload,
              expectedVersion: 0,
            );
        local = await store.load(scope, fileSlot);
        fileLocal = local;
        if (!_currentFile(epoch)) return;
        final ready = await fileGateway.complete(
          scope,
          staged,
          checksum,
          pending.envelope.idempotencyKey,
        );
        if (ready.id != staged.id ||
            ready.tenantId != scope.tenantId ||
            ready.fields['upload_status'] != 'ready') {
          throw const FormatException('Completed file identity mismatch.');
        }
        await store.complete(scope, fileSlot, pending.envelope.commandId);
        if (_disposed) return;
        fileLocal = null;
        complete = true;
      }
    } on DomainError catch (failure) {
      final pending = fileLocal?.pending;
      if (pending != null) {
        await store.recordFailure(
          scope,
          fileSlot,
          failure,
          commandId: pending.envelope.commandId,
        );
        fileLocal = await store.load(scope, fileSlot);
      }
      if (_currentFile(epoch)) {
        if (const {
          'PERMISSION_DENIED',
          'AUTHENTICATION_REQUIRED',
          'MFA_REQUIRED',
        }.contains(failure.code)) {
          clear();
        }
        error = failure.message;
      }
    } catch (failure) {
      if (_currentFile(epoch)) {
        error = failure is FormatException ? failure.message : 'The file outcome is unconfirmed. Reselect the original file or retry confirmation.';
      }
    } finally {
      if (_currentFile(epoch)) {
        busy = false;
        emit();
        if (complete) await refresh();
      }
    }
  }

  bool _currentFile(int epoch) => !_disposed && online && epoch == _epoch;

  Future<void> rejectAttachment(
    Map<String, Object?>? attachment,
    String? reason,
  ) async {
    final store = drafts;
    if (_disposed ||
        busy ||
        !online ||
        !verified ||
        target.id == null ||
        store == null) {
      return;
    }
    busy = true;
    error = null;
    final epoch = _epoch;
    emit();
    var completed = false;
    try {
      var local = rejectionLocal;
      if (local?.pending == null) {
        if (local != null) {
          await store.discard(scope, rejectionSlot);
          rejectionLocal = null;
        }
        final id = attachment?['id'];
        final version = attachment?['version'];
        final text = reason?.trim() ?? '';
        final available =
            (evidence['attachments'] as List?)?.any(
              (item) =>
                  item is Map &&
                  item['id'] == id &&
                  item['upload_status'] == 'ready' &&
                  item['version'] == version,
            ) ??
            false;
        if (!available ||
            id is! String ||
            version is! int ||
            text.length < 3 ||
            text.length > 1000) {
          throw const FormatException(
            'Choose a current ready file and give a reason.',
          );
        }
        final payload = <String, Object?>{
          'id': id,
          'aggregate_type': target.kind,
          'aggregate_id': target.id,
          'reason': text,
        };
        await store.save(
          scope,
          rejectionSlot,
          payload,
          expectedVersion: version,
        );
        await store.prepare(
          scope,
          rejectionSlot,
          verb: 'reject',
          payload: payload,
          expectedVersion: version,
        );
        local = await store.load(scope, rejectionSlot);
        rejectionLocal = local;
      }
      if (!_currentFile(epoch) || local?.pending == null) return;
      final sealed = local!.pending!.envelope;
      if (sealed.payload['aggregate_type'] != target.kind ||
          sealed.payload['aggregate_id'] != target.id) {
        throw const FormatException(
          'Saved rejection belongs to another document.',
        );
      }
      await gateway.rejectAttachment(sealed);
      await store.complete(scope, rejectionSlot, sealed.commandId);
      if (!_currentFile(epoch)) return;
      rejectionLocal = null;
      completed = true;
    } on DomainError catch (failure) {
      final pending = rejectionLocal?.pending;
      if (pending != null) {
        await store.recordFailure(
          scope,
          rejectionSlot,
          failure,
          commandId: pending.envelope.commandId,
        );
        rejectionLocal = await store.load(scope, rejectionSlot);
      }
      if (_currentFile(epoch)) {
        if (const {
          'PERMISSION_DENIED',
          'AUTHENTICATION_REQUIRED',
          'MFA_REQUIRED',
        }.contains(failure.code)) {
          clear();
        }
        error = failure.message;
      }
    } catch (failure) {
      if (_currentFile(epoch)) {
        error = failure is FormatException ? failure.message : 'The file rejection outcome is unconfirmed. Retry the saved request.';
      }
    } finally {
      if (_currentFile(epoch)) {
        busy = false;
        emit();
        if (completed) await refresh();
      }
    }
  }

  void _validateFilters(Map<String, Object?> candidate) {
    if (candidate.keys.any(
          (key) =>
              !const {'search', 'status', 'from_date', 'to_date'}.contains(key),
        ) ||
        candidate.values.any((value) => value is! String) ||
        (candidate['search'] as String? ?? '').length > 200 ||
        (candidate['status'] as String? ?? '').length > 80) {
      throw const FormatException('Unsupported document filter.');
    }
    for (final key in const ['from_date', 'to_date']) {
      final value = candidate[key] as String?;
      if (value == null) continue;
      final date = DateTime.tryParse(value);
      if (date == null || date.toIso8601String().substring(0, 10) != value) {
        throw const FormatException('Use YYYY-MM-DD for document dates.');
      }
    }
    final from = candidate['from_date'] as String?;
    final to = candidate['to_date'] as String?;
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw const FormatException('Start date must be on or before end date.');
    }
  }

  Future<void> next() async {
    if (verified && nextCursor != null) {
      await read(nextCursor, [...previousPages, cursor]);
    }
  }

  Future<void> previous() async {
    if (verified && previousPages.isNotEmpty) {
      await read(
        previousPages.last,
        previousPages.sublist(0, previousPages.length - 1),
      );
    }
  }
}
