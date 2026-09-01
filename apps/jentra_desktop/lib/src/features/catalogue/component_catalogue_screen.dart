import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

class ComponentCatalogueScreen extends StatelessWidget {
  const ComponentCatalogueScreen({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(JentraSpacing.x6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Design system catalogue',
          description:
              'One semantic token system across light, dark, compact and comfortable modes.',
          trailing: JentraStatusBadge(
            label: 'Greenfield v0.1',
            tone: JentraStatusTone.success,
          ),
        ),
        const SizedBox(height: JentraSpacing.x6),
        JentraPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Actions', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: JentraSpacing.x4),
              Wrap(
                spacing: JentraSpacing.x3,
                runSpacing: JentraSpacing.x3,
                children: [
                  JentraPrimaryButton(
                    label: 'Post document',
                    icon: Icons.check,
                    onPressed: () {},
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                  const JentraPrimaryButton(
                    label: 'Posting…',
                    loading: true,
                    onPressed: null,
                  ),
                ],
              ),
              const SizedBox(height: JentraSpacing.x6),
              Text('Status', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: JentraSpacing.x4),
              const Wrap(
                spacing: JentraSpacing.x3,
                runSpacing: JentraSpacing.x3,
                children: [
                  JentraStatusBadge(
                    label: 'Draft',
                    tone: JentraStatusTone.neutral,
                  ),
                  JentraStatusBadge(
                    label: 'Approved',
                    tone: JentraStatusTone.success,
                  ),
                  JentraStatusBadge(
                    label: 'Needs review',
                    tone: JentraStatusTone.warning,
                  ),
                  JentraStatusBadge(
                    label: 'Rejected',
                    tone: JentraStatusTone.danger,
                  ),
                  JentraStatusBadge(
                    label: 'Synchronized',
                    tone: JentraStatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: JentraSpacing.x6),
              Text('Fields', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: JentraSpacing.x4),
              const Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Customer',
                        hintText: 'Search parties',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(width: JentraSpacing.x4),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Invoice amount',
                        prefixText: 'LKR  ',
                        hintText: '0.00',
                      ),
                    ),
                  ),
                  SizedBox(width: JentraSpacing.x4),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Posting date',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        const Row(
          children: [
            Expanded(
              child: JentraKpiCard(
                label: 'Available balance',
                value: 'LKR 6.28M',
                helper: 'Healthy',
                icon: Icons.account_balance_wallet_outlined,
                tone: JentraStatusTone.success,
              ),
            ),
            SizedBox(width: JentraSpacing.x4),
            Expanded(
              child: JentraKpiCard(
                label: 'Overdue invoices',
                value: 'LKR 620K',
                helper: '12 require action',
                icon: Icons.warning_amber_rounded,
                tone: JentraStatusTone.warning,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
