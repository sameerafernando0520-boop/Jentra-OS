import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/company_state.dart';
import 'company_feedback.dart';

/// Prevents company-scoped screens from rendering until a valid company has
/// been selected. Future business repositories must also require the selected
/// company ID when issuing queries.
final class CompanyContextGate extends ConsumerWidget {
  const CompanyContextGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyState = ref.watch(companyControllerProvider);
    final selectedCompanyId = ref.watch(selectedCompanyIdProvider);

    return companyState.when(
      loading: () => const _GateLoadingView(),
      error: (error, _) => _GateErrorView(
        message: CompanyFeedback.userMessage(error),
        onRetry: () =>
            ref.read(companyControllerProvider.notifier).refreshCompanies(),
      ),
      data: (state) {
        if (!state.hasCompanies) {
          return const CompanyRouteRedirect(location: '/company/onboarding');
        }

        if (selectedCompanyId == null) {
          return const CompanyRouteRedirect(location: '/company/select');
        }

        return child;
      },
    );
  }
}

final class _GateLoadingView extends StatelessWidget {
  const _GateLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading company workspace',
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

final class _GateErrorView extends StatelessWidget {
  const _GateErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 42,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Company workspace unavailable',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation is deferred until after the current frame so route resolution
/// never mutates the widget tree during build.
final class CompanyRouteRedirect extends StatefulWidget {
  const CompanyRouteRedirect({required this.location, super.key});

  final String location;

  @override
  State<CompanyRouteRedirect> createState() => _CompanyRouteRedirectState();
}

final class _CompanyRouteRedirectState extends State<CompanyRouteRedirect> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleNavigation();
  }

  @override
  void didUpdateWidget(covariant CompanyRouteRedirect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _scheduled = false;
      _scheduleNavigation();
    }
  }

  void _scheduleNavigation() {
    if (_scheduled) return;
    _scheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentLocation = GoRouterState.of(context).uri.path;
      if (currentLocation != widget.location) {
        context.go(widget.location);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _GateLoadingView();
  }
}
