import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'quotation_scope_guard.dart';

Future<QuotationReference?> showQuotationReferencePicker(
  BuildContext context, {
  required String title,
  required QuotationReferenceKind kind,
  String permission = 'sales.quotations.manage',
  String? customerId,
  String? fromCurrency,
  String? toCurrency,
  QuotationDialogAccess? originAccess,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final scope = container.read(activeTenantContextProvider);
  final original = container.read(businessCapabilitiesProvider);
  final capabilities = original.value;
  if (scope == null || capabilities == null) return null;
  final access = originAccess ?? QuotationDialogAccess(context);
  bool current() {
    if (!context.mounted) return false;
    final caps = container.read(businessCapabilitiesProvider);
    final connection = container.read(connectivityStateProvider);
    return container.read(activeTenantContextProvider) == scope &&
        !caps.isLoading &&
        !caps.hasError &&
        caps.value?.contains(permission) == true &&
        caps.value!.length == capabilities.length &&
        caps.value!.containsAll(capabilities) &&
        !connection.isLoading &&
        !connection.hasError &&
        connection.value == ConnectivityState.online;
  }

  void observe() {
    if (!current()) access.denyReadAccess();
  }

  final scopes = container.listen(
    activeTenantContextProvider,
    (_, _) => observe(),
  );
  final caps = container.listen(
    businessCapabilitiesProvider,
    (_, _) => observe(),
  );
  final connections = container.listen(
    connectivityStateProvider,
    (_, _) => observe(),
  );
  ModalRoute.of(context)?.popped.then((_) => access.denyReadAccess());
  observe();
  try {
    return await showOperationalReadDialog<QuotationReference>(
      context,
      access,
      (_) => _ReferencePicker(
        title: title,
        permission: permission,
        kind: kind,
        access: access,
        customerId: customerId,
        fromCurrency: fromCurrency,
        toCurrency: toCurrency,
      ),
    );
  } finally {
    scopes.close();
    caps.close();
    connections.close();
    if (originAccess == null) access.dispose();
  }
}

class _ReferencePicker extends ConsumerStatefulWidget {
  const _ReferencePicker({
    required this.title,
    required this.permission,
    required this.kind,
    required this.access,
    this.customerId,
    this.fromCurrency,
    this.toCurrency,
  });
  final String title, permission;
  final QuotationReferenceKind kind;
  final OperationalReadAccess access;
  final String? customerId;
  final String? fromCurrency;
  final String? toCurrency;
  @override
  ConsumerState<_ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends ConsumerState<_ReferencePicker> {
  final _search = TextEditingController();
  CursorPage<QuotationReference>? _page;
  List<QuotationReference> _items = [];
  Object? _error;
  bool _loading = true;
  int _request = 0;
  TenantContext? _scope;
  Set<String>? _capabilities;
  late final int _accessEpoch;

  @override
  void initState() {
    super.initState();
    _accessEpoch = widget.access.readAccessEpoch;
    _scope = ref.read(activeTenantContextProvider);
    _capabilities = ref.read(businessCapabilitiesProvider).value;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_request;
    if (!_valid(generation)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _items = [];
    });
    try {
      final repository = ref.read(quotationReferenceRepositoryProvider);
      if (_scope == null || repository == null) {
        throw const DomainError(
          code: 'BACKEND_UNAVAILABLE',
          message: 'Reference data is unavailable.',
        );
      }
      final page = await repository.pageReferences(
        context: _scope!,
        kind: widget.kind,
        query: QuotationReferenceQuery(
          search: _search.text,
          cursor: more ? _page?.nextCursor : null,
          customerId: widget.customerId,
          fromCurrency: widget.fromCurrency,
          toCurrency: widget.toCurrency,
        ),
      );
      if (!_valid(generation)) return;
      setState(() {
        _page = page;
        _items = [..._items, ...page.items];
        _loading = false;
      });
    } on Object catch (error) {
      if (!_valid(generation)) return;
      if (error is DomainError &&
          {
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
            'TENANT_ACCESS_DENIED',
          }.contains(error.code)) {
        widget.access.denyReadAccess();
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  bool _valid(int generation) =>
      mounted &&
      widget.access.currentRead(_accessEpoch) &&
      generation == _request &&
      _scope == ref.read(activeTenantContextProvider) &&
      !ref.read(businessCapabilitiesProvider).isLoading &&
      !ref.read(businessCapabilitiesProvider).hasError &&
      !ref.read(connectivityStateProvider).isLoading &&
      !ref.read(connectivityStateProvider).hasError &&
      ref.read(connectivityStateProvider).value == ConnectivityState.online &&
      ref
              .read(businessCapabilitiesProvider)
              .value
              ?.contains(widget.permission) ==
          true &&
      _sameCapabilities(ref.read(businessCapabilitiesProvider).value);
  bool _sameCapabilities(Set<String>? current) =>
      current != null &&
      _capabilities != null &&
      current.length == _capabilities!.length &&
      current.containsAll(_capabilities!);

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(activeTenantContextProvider);
    final capabilities = ref.watch(businessCapabilitiesProvider);
    final connection = ref.watch(connectivityStateProvider);
    final online =
        !connection.isLoading &&
        !connection.hasError &&
        connection.value == ConnectivityState.online;
    final active =
        widget.access.currentRead(_accessEpoch) &&
        scope == _scope &&
        !capabilities.isLoading &&
        !capabilities.hasError &&
        capabilities.value?.contains(widget.permission) == true &&
        _sameCapabilities(capabilities.value) &&
        online;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 430,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              enabled: active,
              decoration: InputDecoration(
                labelText: 'Search ${widget.title.toLowerCase()}',
                suffixIcon: IconButton(
                  tooltip: 'Search references',
                  onPressed: active ? _load : null,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: active ? (_) => _load() : null,
            ),
            const SizedBox(height: 12),
            if (!active)
              const Expanded(
                child: Center(
                  child: Text(
                    'Scope, access or connection changed. Close this picker and reopen it when ready.',
                  ),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error is DomainError
                          ? (_error as DomainError).message
                          : 'Could not load reference data.',
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final item in _items)
                      ListTile(
                        title: Text(item.label),
                        subtitle: item.values['effective_date'] != null
                            ? Text(
                                'Effective ${item.values['effective_date']} · Rate ${item.values['rate']}',
                              )
                            : null,
                        onTap: () {
                          if (_valid(_request)) Navigator.of(context).pop(item);
                        },
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Loading governed references',
                          ),
                        ),
                      ),
                    if (!_loading && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No available records. Check the search and your reference-data permissions.',
                        ),
                      ),
                    if (!_loading && (_page?.hasNextPage ?? false))
                      TextButton(
                        onPressed: () => _load(more: true),
                        child: const Text('Load more references'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
