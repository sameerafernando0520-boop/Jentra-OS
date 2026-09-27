import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';

/// Read-only boundary evidence. It neither captures nor approves work time.
class CalendarResolutionDialog extends StatefulWidget {
  const CalendarResolutionDialog({
    required this.resolver,
    required this.scope,
    required this.version,
    required this.isCurrent,
    super.key,
  });
  final CalendarInstantResolver resolver;
  final TenantContext scope;
  final CalendarVersionDetail version;
  final bool Function() isCurrent;
  @override
  State<CalendarResolutionDialog> createState() =>
      _CalendarResolutionDialogState();
}

class _CalendarResolutionDialogState extends State<CalendarResolutionDialog> {
  late final date = TextEditingController(
    text: widget.version.summary.coverage.start.value,
  );
  final time = TextEditingController(text: '09:00');
  CalendarLocalResolution? resolution;
  CalendarInstant? chosen;
  String? error;
  bool busy = false;
  int generation = 0;
  @override
  void didUpdateWidget(CalendarResolutionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isCurrent() ||
        oldWidget.scope != widget.scope ||
        oldWidget.version.summary.coverage.id !=
            widget.version.summary.coverage.id) {
      generation++;
      resolution = null;
      chosen = null;
      error = null;
      busy = false;
    }
  }

  @override
  void dispose() {
    date.dispose();
    time.dispose();
    super.dispose();
  }

  void invalidate() {
    generation++;
    setState(() {
      resolution = null;
      chosen = null;
      error = null;
    });
  }

  Future<void> resolve() async {
    if (busy || !widget.isCurrent()) return;
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
      resolution = null;
      chosen = null;
    });
    try {
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time.text)) {
        throw const FormatException('Use a local time from 00:00 to 23:59.');
      }
      final value = await widget.resolver.localCandidates(
        widget.scope,
        widget.version,
        CivilDate.parse(date.text),
        int.parse(time.text.substring(0, 2)) * 60 +
            int.parse(time.text.substring(3)),
      );
      if (!mounted || current != generation || !widget.isCurrent()) return;
      setState(() {
        resolution = value;
        chosen = value.candidates.length == 1 ? value.choose() : null;
      });
    } catch (cause) {
      if (!mounted || current != generation || !widget.isCurrent()) return;
      setState(() {
        error = cause is DomainError
            ? cause.message
            : cause is FormatException
            ? cause.message
            : 'Local-time resolution is unavailable. Retry when connected.';
      });
    } finally {
      if (mounted && current == generation) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent()) {
      return AlertDialog(
        title: const Text('Calendar access changed'),
        content: const Text('Close this preview and reload calendar access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Resolve a local time'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.version.summary.coverage.timezone} · Published version',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: date,
                enabled: !busy,
                onChanged: (_) => invalidate(),
                decoration: const InputDecoration(
                  labelText: 'Local date',
                  helperText: 'YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: time,
                enabled: !busy,
                onChanged: (_) => invalidate(),
                decoration: const InputDecoration(
                  labelText: 'Local time',
                  helperText: 'HH:MM',
                ),
              ),
              if (resolution?.isGap ?? false) ...[
                const SizedBox(height: 16),
                const Text(
                  'This local time does not exist. Choose another boundary.',
                ),
              ],
              if (resolution?.isAmbiguous ?? false) ...[
                const SizedBox(height: 16),
                const Text(
                  'This local time occurs twice. Choose its UTC offset.',
                ),
                for (final instant in resolution!.candidates)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: () {
                        if (!widget.isCurrent()) return;
                        setState(() {
                          chosen = resolution!.choose(
                            offsetSeconds: instant.offsetSeconds,
                          );
                        });
                      },
                      child: Text(
                        '${instant.offsetSeconds} offset seconds · ${instant.utc.toIso8601String()}',
                      ),
                    ),
                  ),
              ],
              if (chosen != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  'UTC ${chosen!.utc.toIso8601String()}\nOffset ${chosen!.offsetSeconds} seconds',
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Boundary preview only. Work intervals retain both boundaries and exact elapsed seconds.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
        OutlinedButton(
          onPressed: busy ? null : resolve,
          child: Text(busy ? 'Resolving…' : 'Resolve time'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
