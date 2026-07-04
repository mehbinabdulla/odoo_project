import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class TimeInputField extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final String? Function(String?)? validator;

  const TimeInputField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.decoration,
    this.style,
    this.validator,
  });

  @override
  State<TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<TimeInputField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatTime(widget.initialValue));
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(TimeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      final newText = _formatTime(widget.initialValue);
      if (_controller.text != newText && _parseTime(_controller.text) != widget.initialValue) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final parsed = _parseTime(_controller.text);
    widget.onChanged(parsed);
  }

  String _formatTime(double value) {
    if (value < 0) value = 0;
    int hours = value.truncate();
    int minutes = ((value - hours) * 60).round();
    if (minutes == 60) {
      hours += 1;
      minutes = 0;
    }
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  double _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      int m = int.tryParse(parts[1]) ?? 0;
      return h + (m / 60.0);
    }
    // Fallback to pure double parsing if user just types "1.5"
    return double.tryParse(timeStr) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: TextInputType.datetime,
      inputFormatters: [
        // Allow digits and colon
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        _TimeTextInputFormatter(),
      ],
      decoration: widget.decoration,
      style: widget.style ?? GoogleFonts.poppins(fontSize: 16),
      validator: widget.validator,
    );
  }
}

class _TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;

    // Handle backspace properly
    if (newText.length < oldValue.text.length) {
      return newValue;
    }

    // Automatically insert colon after 2 digits if there isn't one
    if (newText.length == 2 && !newText.contains(':')) {
      return TextEditingValue(
        text: '$newText:',
        selection: const TextSelection.collapsed(offset: 3),
      );
    }

    // Limit length to 5 characters (HH:MM)
    if (newText.length > 5) {
      return oldValue;
    }

    return newValue;
  }
}
