import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import 'quotation_controller.dart';

typedef _ReferenceKey = ({
  QuotationReferenceKind kind,
  String id,
  String? customerId,
  bool orderMode,
});
final _referenceNameProvider = FutureProvider.autoDispose
    .family<String?, _ReferenceKey>((ref, key) async {
      final scope = ref.watch(activeTenantContextProvider);
      final capabilities = ref.watch(businessCapabilitiesProvider);
      final repository = ref.watch(quotationReferenceRepositoryProvider);
      final online =
          ref.watch(connectivityStateProvider).value ==
          ConnectivityState.online;
      if (scope == null ||
          repository == null ||
          !online ||
          capabilities.isLoading ||
          capabilities.hasError ||
          !(key.orderMode
              ? const {
                  'sales.orders.view',
                  'sales.orders.manage',
                }.any((capabilities.value ?? {}).contains)
              : canViewQuotations(capabilities.value ?? {}))) {
        return null;
      }
      final page = await repository.pageReferences(
        context: scope,
        kind: key.kind,
        query: QuotationReferenceQuery(
          id: key.id,
          customerId: key.customerId,
          limit: 1,
        ),
      );
      return page.items.where((item) => item.id == key.id).firstOrNull?.label;
    }, retry: (count, error) => null);

/// Names are from the current governed directory; immutable IDs remain the reference.
class QuotationReferenceLabel extends ConsumerWidget {
  const QuotationReferenceLabel({
    required this.kind,
    required this.id,
    this.customerId,
    this.savedLabel,
    this.resolveCurrentName = true,
    this.orderMode = false,
    super.key,
  });
  final QuotationReferenceKind kind;
  final String id;
  final String? customerId, savedLabel;
  final bool resolveCurrentName, orderMode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (savedLabel != null) return Text(savedLabel!);
    if (!resolveCurrentName) return Text(id);
    final name = ref
        .watch(
          _referenceNameProvider((
            kind: kind,
            id: id,
            customerId: customerId,
            orderMode: orderMode,
          )),
        )
        .value;
    return Tooltip(
      message: name == null ? id : 'Current reference name · $id',
      child: Text(name ?? id),
    );
  }
}
