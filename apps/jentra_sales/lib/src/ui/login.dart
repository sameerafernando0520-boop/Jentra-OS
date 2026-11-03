import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../sales_controller.dart';
import 'components.dart';

class SalesLogin extends StatefulWidget {
  const SalesLogin(this.controller, {super.key});
  final SalesController controller;
  @override
  State<SalesLogin> createState() => _SalesLoginState();
}

class _SalesLoginState extends State<SalesLogin> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _password.clear();
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final password = _password.text;
    _password.clear();
    await widget.controller.signIn(_email.text.trim(), password);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, box) {
        final textScale = MediaQuery.textScalerOf(context)
            .scale(1)
            .clamp(1.0, double.infinity);
        final wide =
            box.maxWidth >= 1050 * textScale &&
            box.maxHeight >= 800 * textScale &&
            textScale < 1.5;
        final form = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(box.maxWidth < 600 ? 24 : 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!wide) ...[
                        JentraBrandLockup(
                          size: 38,
                          inverse:
                              Theme.of(context).brightness == Brightness.dark,
                        ),
                        const SizedBox(height: 40),
                      ],
                      const Text(
                        'JENTRA SALES',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                          color: salesBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        header: true,
                        child: Text(
                          'Your next great\nsale starts here.',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: -1,
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Use your Jentra OS work account. Your company controls access to customers and orders.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Work email',
                          hintText: 'you@company.com',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (v) =>
                            v != null &&
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(v.trim())
                            ? null
                            : 'Enter your work email.',
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _password,
                        obscureText: !_visible,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!widget.controller.busy) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _visible
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _visible = !_visible),
                            icon: Icon(
                              _visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: widget.controller.busy ? null : _submit,
                          child: Text(
                            widget.controller.busy
                                ? 'Please wait…'
                                : 'Sign in to your company',
                          ),
                        ),
                      ),
                      if (widget.controller.notice != null) ...[
                        const SizedBox(height: 20),
                        SalesNotice(widget.controller.notice!),
                      ],
                      const SizedBox(height: 28),
                      const Center(
                        child: Text(
                          'NEW TO JENTRA SALES?',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.controller.busy
                              ? null
                              : widget.controller.enterPreview,
                          icon: const Icon(Icons.play_circle_outline, size: 20),
                          label: const Text('Explore the preview'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Try the complete interface with sample data. Preview changes never create real orders.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 36),
                      Center(
                        child: Text(
                          'Operate. Connect. Grow.  ·  v0.1.1 Development',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return SafeArea(
          child: Row(
            children: [
              if (wide) Expanded(child: _WelcomePanel()),
              Expanded(child: form),
            ],
          ),
        );
      },
    ),
  );
}

class _WelcomePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: salesNavy,
    padding: const EdgeInsets.all(56),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraBrandLockup(size: 40, inverse: true),
        const Spacer(),
        const Text(
          'Less admin.\nMore connections.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 48,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'From the first conversation to the final delivery,\nkeep every next step in view.',
          style: TextStyle(color: Color(0xFFACBECE), fontSize: 17, height: 1.6),
        ),
        const SizedBox(height: 44),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF102E49),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF23435F)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF73DBBC)),
                  SizedBox(width: 12),
                  Text(
                    'EVERY STEP, CONNECTED',
                    style: TextStyle(
                      color: Color(0xFFACBECE),
                      fontSize: 11,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              _WelcomeStep(
                Icons.people_outline,
                'Know your customers',
                'Your assigned portfolio, always in focus.',
              ),
              SizedBox(height: 24),
              _WelcomeStep(
                Icons.receipt_long_outlined,
                'Build better orders',
                'Clear prices, careful review, fewer loose ends.',
              ),
              SizedBox(height: 24),
              _WelcomeStep(
                Icons.local_shipping_outlined,
                'Follow through',
                'Customer response, company review and delivery.',
              ),
            ],
          ),
        ),
        const Spacer(),
        const Text(
          'BUILT FOR THE WAY YOU SELL.',
          style: TextStyle(
            color: Color(0xFFACBECE),
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep(this.icon, this.title, this.description);
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: const Color(0xFF68B7FF), size: 24),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(color: Color(0xFFACBECE), fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}
