import 'package:flutter/material.dart';

import 'customer_list_screen.dart';

/// CRM currently opens on Customers. Suppliers, Leads, and Activities will be
/// added as sibling CRM destinations without changing this route contract.
final class CrmScreen extends StatelessWidget {
  const CrmScreen({super.key});

  @override
  Widget build(BuildContext context) => const CustomerListScreen();
}
