import 'package:flutter/material.dart';

class ToggleButton extends StatefulWidget {
  final String text;
  final String selectedText;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;

  const ToggleButton({
    super.key,
    required this.text,
    selectedText,
    this.initialValue = false,
    this.onChanged,
  }) : selectedText = selectedText ?? text;

  @override
  ToggleButtonState createState() => ToggleButtonState();
}

class ToggleButtonState extends State<ToggleButton> {
  late bool _isOn;

  @override
  void initState() {
    super.initState();
    _isOn = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _isOn = !_isOn);
        widget.onChanged?.call(_isOn);
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: .symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: _isOn ? Colors.blue : Colors.grey,
          borderRadius: .circular(16),
        ),
        child: Text(
          _isOn ? widget.selectedText : widget.text,
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}
