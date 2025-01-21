import 'package:flutter/material.dart';

class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;

  const CustomButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  CustomButtonState createState() => CustomButtonState();
}

class CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;
  bool get _isDisabled => widget.onPressed == null;

  Future<void> _handleTap() async {
    setState(() {
      _isPressed = true;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    setState(() {
      _isPressed = false;
    });

    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color borderColor = _isPressed
        ? theme.colorScheme.primary
        : _isDisabled
            ? theme.disabledColor
            : theme.dividerColor;
    final Color containerColor = _isPressed
        ? theme.colorScheme.primary.withAlpha(50)
        : _isDisabled
            ? theme.disabledColor.withValues(alpha: 0.2)
            : Colors.transparent;

    final Color textColor = _isPressed
        ? theme.colorScheme.primary
        : _isDisabled
            ? theme.disabledColor
            : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: _isDisabled ? null : _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: containerColor,
          border: Border.all(
            color: borderColor,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: textColor,
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
