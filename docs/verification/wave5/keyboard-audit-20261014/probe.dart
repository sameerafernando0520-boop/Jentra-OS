import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Standalone synthetic receiver. No product imports, file storage or network.
void main() => runApp(const KeyboardProbeApp());

class KeyboardProbeApp extends StatelessWidget {
  const KeyboardProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jentra Keyboard Probe - TEST ONLY',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const KeyboardProbePage(),
  );
}

class KeyboardProbePage extends StatefulWidget {
  const KeyboardProbePage({super.key});

  @override
  State<KeyboardProbePage> createState() => _KeyboardProbePageState();
}

class _KeyboardProbePageState extends State<KeyboardProbePage>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _fieldFocus = FocusNode();
  final _events = <String>[];
  int _acceptedCtrlK = 0;
  bool _foreground = true;

  static const _allowed = <LogicalKeyboardKey>{
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.escape,
  };

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_observe);
    _text.addListener(_redraw);
    _fieldFocus.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _redraw();
  }

  String _key(LogicalKeyboardKey key) =>
      '${key.debugName ?? 'unnamed'}:0x${key.keyId.toRadixString(16)}';

  bool _observe(KeyEvent event) {
    if (!mounted || !_foreground || !_fieldFocus.hasFocus) return false;
    if (event is! KeyDownEvent && event is! KeyUpEvent) return false;
    if (!_allowed.contains(event.logicalKey)) return false;
    final keyboard = HardwareKeyboard.instance;
    final pressed = keyboard.logicalKeysPressed
        .where(_allowed.contains)
        .map(_key)
        .toList()
      ..sort();
    final ctrlK = const SingleActivator(
      LogicalKeyboardKey.keyK,
      control: true,
    ).accepts(event, keyboard);
    final line =
        '${event is KeyDownEvent ? 'DOWN' : 'UP'} '
        'logical=${_key(event.logicalKey)} '
        'physical=${event.physicalKey.debugName ?? 'unnamed'}:'
        '0x${event.physicalKey.usbHidUsage.toRadixString(16)} '
        'ctrl=${keyboard.isControlPressed} '
        'shift=${keyboard.isShiftPressed} alt=${keyboard.isAltPressed} '
        'synth=${event.synthesized} pressed=[${pressed.take(12).join(', ')}]';
    setState(() {
      if (ctrlK) _acceptedCtrlK++;
      _events.add(line);
      if (_events.length > 8) _events.removeAt(0);
    });
    // Observation must not consume the normal TextField editing/shortcut path.
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_observe);
    WidgetsBinding.instance.removeObserver(this);
    _text.removeListener(_redraw);
    _fieldFocus.removeListener(_redraw);
    _text.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Jentra Keyboard Probe - TEST ONLY')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Synthetic text only. Never enter passwords or private data. '
              'Nothing is saved or sent. Click the test field before a trial.',
            ),
            const SizedBox(height: 8),
            Text('Local field focus: ${_fieldFocus.hasFocus}; '
                'window active: $_foreground'),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              focusNode: _fieldFocus,
              autofocus: true,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Synthetic test field',
                border: OutlineInputBorder(),
              ),
            ),
            Text('Typed synthetic text: ${_text.text}'),
            Text('Selection: ${_text.selection.baseOffset}:'
                '${_text.selection.extentOffset}'),
            Text('Accepted Control+K: $_acceptedCtrlK'),
            const SizedBox(height: 12),
            const Text('Last eight allowlisted local key events '
                '(no character payload, clipboard, device or global input capture):'),
            const SizedBox(height: 8),
            for (final event in _events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(event, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    ),
  );
