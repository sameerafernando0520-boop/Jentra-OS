import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';

final class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

final class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  bool _tenantBoundaryEnforced = true;
  bool _readOnlyMode = true;
  bool _contextSummariesEnabled = true;
  String _selectedModel = 'Local Rule Engine / Gemini Edge';

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'AI Privacy & Data Boundaries (${company.name})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Jentra OS AI Assistant operates under strict tenant boundary rules. Customer data from other companies is completely inaccessible.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Strict Tenant Boundary Enforcement'),
            subtitle: const Text('Isolate all queries strictly to selected company ID'),
            value: _tenantBoundaryEnforced,
            onChanged: (val) => setState(() => _tenantBoundaryEnforced = val),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Read-Only Data Access'),
            subtitle: const Text('AI cannot execute mutations or delete records'),
            value: _readOnlyMode,
            onChanged: (val) => setState(() => _readOnlyMode = val),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Business Context Summary Generation'),
            subtitle: const Text('Provide revenue and balance metrics to AI assistant'),
            value: _contextSummariesEnabled,
            onChanged: (val) => setState(() => _contextSummariesEnabled = val),
          ),
          const Divider(),
          ListTile(
            title: const Text('AI Execution Provider'),
            subtitle: Text(_selectedModel),
            trailing: DropdownButton<String>(
              value: _selectedModel,
              items: const [
                DropdownMenuItem(
                  value: 'Local Rule Engine / Gemini Edge',
                  child: Text('Local Rule Engine / Gemini Edge'),
                ),
                DropdownMenuItem(
                  value: 'Supabase Edge Function AI Gateway',
                  child: Text('Supabase Edge Function Gateway'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedModel = val);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
