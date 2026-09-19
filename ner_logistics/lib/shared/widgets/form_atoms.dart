import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Form atoms — reused across Login, Create Account, and Report Incident screens.
///
///   FieldLabel        — uppercase 10sp eyebrow label above every field
///   LabeledInput      — label + text input with optional type and error
///   LabeledSelect     — label + dropdown picker
///   GlassPasswordField — password input with show/hide toggle + error
///   GlassField        — full glass-styled input (used on Login glass card)
///   GlassSelect       — glass-styled dropdown (used on Login glass card)

// ── FieldLabel ────────────────────────────────────────────────────────────────

class FieldLabel extends StatelessWidget {
  final String text;
  final bool optional;

  const FieldLabel(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: AppTextStyles.eyebrow.copyWith(
            color: AppColors.navy900.withOpacity(0.55),
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Text(
            'Optional',
            style: AppTextStyles.caption.copyWith(
                color: AppColors.slate500.withOpacity(0.4)),
          ),
        ],
      ],
    );
  }
}

// ── LabeledInput ──────────────────────────────────────────────────────────────

class LabeledInput extends StatefulWidget {
  final String label;
  final String? initialValue;
  final String? placeholder;
  final TextInputType keyboardType;
  final bool optional;
  final String? error;
  final ValueChanged<String>? onChanged;

  const LabeledInput({
    super.key,
    required this.label,
    this.initialValue,
    this.placeholder,
    this.keyboardType = TextInputType.text,
    this.optional = false,
    this.error,
    this.onChanged,
  });

  @override
  State<LabeledInput> createState() => _LabeledInputState();
}

class _LabeledInputState extends State<LabeledInput> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label, optional: widget.optional),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            style: AppTextStyles.inputText,
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: AppTextStyles.inputHint,
              errorText: widget.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ── LabeledSelect ─────────────────────────────────────────────────────────────

class LabeledSelect extends StatefulWidget {
  final String label;
  final String? value;
  final List<String> options;
  final String? placeholder;
  final ValueChanged<String?>? onChanged;

  const LabeledSelect({
    super.key,
    required this.label,
    this.value,
    required this.options,
    this.placeholder,
    this.onChanged,
  });

  @override
  State<LabeledSelect> createState() => _LabeledSelectState();
}

class _LabeledSelectState extends State<LabeledSelect> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selected,
            hint: widget.placeholder != null
                ? Text(widget.placeholder!,
                    style: AppTextStyles.inputHint)
                : null,
            style: AppTextStyles.inputText,
            decoration: const InputDecoration(),
            items: widget.options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              setState(() => _selected = v);
              widget.onChanged?.call(v);
            },
          ),
        ],
      ),
    );
  }
}

// ── GlassPasswordField ────────────────────────────────────────────────────────

class GlassPasswordField extends StatefulWidget {
  final String? placeholder;
  final String? error;
  final ValueChanged<String>? onChanged;

  const GlassPasswordField({
    super.key,
    this.placeholder,
    this.error,
    this.onChanged,
  });

  @override
  State<GlassPasswordField> createState() => _GlassPasswordFieldState();
}

class _GlassPasswordFieldState extends State<GlassPasswordField> {
  bool _show = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasError
                    ? AppColors.signalRed700
                    : AppColors.navy900.withOpacity(0.15),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    obscureText: !_show,
                    onChanged: widget.onChanged,
                    style: AppTextStyles.inputText,
                    decoration: InputDecoration(
                      hintText: widget.placeholder,
                      hintStyle: AppTextStyles.inputHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _show = !_show),
                  child: Text(
                    _show ? 'Hide' : 'Show',
                    style: AppTextStyles.buttonSmall.copyWith(
                        color: AppColors.navy900.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.warning_outlined,
                      size: 13, color: AppColors.signalRed700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.error!,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.signalRed700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── GlassField ────────────────────────────────────────────────────────────────
// Used on the login glass card — white bg, rounded-lg, navy hairline border.

class GlassField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final String? placeholder;
  final TextInputType keyboardType;
  final bool optional;
  final ValueChanged<String>? onChanged;

  const GlassField({
    super.key,
    required this.label,
    this.initialValue,
    this.placeholder,
    this.keyboardType = TextInputType.text,
    this.optional = false,
    this.onChanged,
  });

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FieldLabel(widget.label),
              if (widget.optional) ...[
                const SizedBox(width: 6),
                Text('Optional',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.slate500.withOpacity(0.4))),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            style: AppTextStyles.inputText,
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: AppTextStyles.inputHint,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(0.5),
                    width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── GlassSelect ───────────────────────────────────────────────────────────────

class GlassSelect extends StatefulWidget {
  final String label;
  final String? value;
  final String placeholder;
  final List<String> options;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

  const GlassSelect({
    super.key,
    required this.label,
    this.value,
    required this.placeholder,
    required this.options,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<GlassSelect> createState() => _GlassSelectState();
}

class _GlassSelectState extends State<GlassSelect> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  void didUpdateWidget(covariant GlassSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        !widget.options.contains(_selected)) {
      _selected = widget.options.contains(widget.value) ? widget.value : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.enabled && widget.options.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: widget.options.contains(_selected) ? _selected : null,
            hint: Text(widget.placeholder,
                style: AppTextStyles.inputHint),
            style: AppTextStyles.inputText,
            decoration: InputDecoration(
              filled: true,
              fillColor: isInteractive ? Colors.white : Colors.white.withOpacity(0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(isInteractive ? 0.15 : 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AppColors.navy900.withOpacity(0.5),
                    width: 1.5),
              ),
            ),
            items: isInteractive
                ? widget.options
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList()
                : null,
            onChanged: isInteractive
                ? (v) {
                    setState(() => _selected = v);
                    widget.onChanged?.call(v);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
