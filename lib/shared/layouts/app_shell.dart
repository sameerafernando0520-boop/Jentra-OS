import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_module.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_models.dart';
import '../../features/auth/presentation/widgets/auth_feedback.dart';
import '../../features/company/application/company_state.dart';
import '../components/brand_mark.dart';

final class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthActionResult?>>(authControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasError && !identical(previous?.error, next.error)) {
        AuthFeedback.showError(context, next.error);
      }
    });

    final authState = ref.watch(authControllerProvider);
    final selectedCompany = ref.watch(selectedCompanyProvider);
    final path = GoRouterState.of(context).uri.path;
    final currentModule = AppModule.fromPath(path);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppConstants.desktopBreakpoint;

    final navigation = _ModuleNavigation(
      currentModule: currentModule,
      closeDrawerAfterSelection: !isDesktop,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentModule.label,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: () => context.go('/company/select'),
                icon: const Icon(Icons.business_outlined, size: 16),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    selectedCompany?.name ?? 'Select company',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: selectedCompany == null
                  ? 'Select company'
                  : 'Switch company: ${selectedCompany.name}',
              onPressed: () => context.go('/company/select'),
              icon: const Icon(Icons.business_outlined),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: authState.isLoading
                  ? null
                  : ref.read(authControllerProvider.notifier).logout,
              icon: authState.isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded, size: 20),
            ),
          ),
        ],
      ),
      drawer: isDesktop ? null : Drawer(child: navigation),
      body: isDesktop
          ? Row(
              children: [
                SizedBox(width: 260, child: navigation),
                const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

final class _ModuleNavigation extends StatelessWidget {
  const _ModuleNavigation({
    required this.currentModule,
    required this.closeDrawerAfterSelection,
  });

  final AppModule currentModule;
  final bool closeDrawerAfterSelection;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: AppModule.values.indexOf(currentModule),
      onDestinationSelected: (index) {
        if (closeDrawerAfterSelection) {
          Navigator.of(context).pop();
        }
        context.go(AppModule.values[index].route);
      },
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: BrandMark(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 16, 12),
          child: Text(
            'ENTERPRISE MODULES',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        for (final module in AppModule.values)
          NavigationDrawerDestination(
            icon: Icon(module.icon, size: 20),
            selectedIcon: Icon(module.icon, size: 20),
            label: Text(
              module.label,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
