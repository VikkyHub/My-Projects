import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/config.dart';
import '../core/theme.dart';

void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));

enum BtnKind { primary, gold, secondary, ghost, danger }

/// Pill button with the brand gradient (or a variant).
class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onPressed, this.icon, this.kind = BtnKind.primary, this.loading = false, this.expand = false, this.small = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BtnKind kind;
  final bool loading, expand, small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (Gradient? grad, Color bg, Color fg, BorderSide? side) = switch (kind) {
      BtnKind.primary => (C.buttonGradient, C.brand600, Colors.white, null),
      BtnKind.gold => (C.goldGradient, C.gold300, C.brand950, null),
      BtnKind.secondary => (null, Colors.white, C.ink, const BorderSide(color: C.line)),
      BtnKind.ghost => (null, Colors.transparent, C.brand700, null),
      BtnKind.danger => (null, C.red, Colors.white, null),
    };
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: small ? 16 : 18, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: small ? 13 : 15))),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: grad,
          color: grad == null ? bg : null,
          borderRadius: BorderRadius.circular(999),
          border: side == null ? null : Border.fromBorderSide(side),
          boxShadow: kind == BtnKind.primary && enabled
              ? [BoxShadow(color: C.brand600.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? onPressed : null,
            child: Padding(padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20, vertical: small ? 9 : 14), child: child),
          ),
        ),
      ),
    );
  }
}

/// White rounded card with the soft brand shadow.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = Colors.white, this.border, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border ?? C.line.withValues(alpha: .8)),
          boxShadow: [BoxShadow(color: C.brand800.withValues(alpha: .07), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.fg = C.brand600, this.bg = C.brand50, this.size = 40});
  final IconData icon;
  final Color fg, bg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .35)),
        child: Icon(icon, color: fg, size: size * .5),
      );
}

/// Small status pill — always icon + text (never colour alone).
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.fg = C.muted, this.bg = C.sand});
  final String label;
  final IconData? icon;
  final Color fg, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFECACA))),
          child: Text(message!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600, fontSize: 13.5)),
        );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key, this.optional = false, this.hint});
  final String label;
  final bool optional;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), children: [
            if (optional) const TextSpan(text: '  optional', style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
          ])),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: const TextStyle(fontSize: 12, color: C.muted))),
        ]),
      );
}

/// Dropdown with a consistent look. `items` = (value, label).
class Pick<T> extends StatelessWidget {
  const Pick({super.key, required this.value, required this.items, required this.onChanged, this.hint = 'Select'});
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final String hint;
  @override
  Widget build(BuildContext context) {
    final valid = items.any((i) => i.$1 == value);
    return DropdownButtonFormField<T>(
      initialValue: valid ? value : null,
      isExpanded: true,
      hint: Text(hint),
      borderRadius: BorderRadius.circular(16),
      items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

/// Six separate OTP boxes; supports paste / SMS autofill.
class OtpField extends StatefulWidget {
  const OtpField({super.key, required this.onChanged, this.onCompleted});
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  final _c = TextEditingController();
  final _f = FocusNode();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _f.requestFocus());
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.text;
    return GestureDetector(
      onTap: () => _f.requestFocus(),
      child: Stack(children: [
        Opacity(
          opacity: 0,
          child: TextField(
            controller: _c,
            focusNode: _f,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (s) {
              setState(() {});
              widget.onChanged(s);
              if (s.length == 6) widget.onCompleted?.call(s);
            },
          ),
        ),
        Row(children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: i == v.length && _f.hasFocus ? C.brand500 : (i < v.length ? C.brand200 : C.line), width: i == v.length && _f.hasFocus ? 2 : 1),
                ),
                child: Text(i < v.length ? v[i] : '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.onChanged, this.autofocus = false});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 1),
        decoration: const InputDecoration(
          counterText: '',
          hintText: '98765 43210',
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 16, right: 10),
            child: Text('🇮🇳  +91', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      );
}

/// Faint mandala motif (same as the web pattern), drawn natively.
class MandalaPainter extends CustomPainter {
  MandalaPainter({this.color = Colors.white, this.opacity = .10, this.tile = 96});
  final Color color;
  final double opacity, tile;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: opacity);
    for (double y = 0; y < size.height + tile; y += tile) {
      for (double x = 0; x < size.width + tile; x += tile) {
        final c = Offset(x + tile / 2, y + tile / 2);
        canvas.drawCircle(c, tile * .05, p);
        canvas.drawCircle(c, tile * .17, p);
        for (var k = 0; k < 8; k++) {
          final a = k * math.pi / 4;
          final tip = c + Offset(math.cos(a), math.sin(a)) * tile * .27;
          final l = c + Offset(math.cos(a + .35), math.sin(a + .35)) * tile * .14;
          final r = c + Offset(math.cos(a - .35), math.sin(a - .35)) * tile * .14;
          canvas.drawPath(Path()..moveTo(c.dx, c.dy)..quadraticBezierTo(l.dx, l.dy, tip.dx, tip.dy)..quadraticBezierTo(r.dx, r.dy, c.dx, c.dy), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant MandalaPainter old) => false;
}

/// Rani-pink gradient panel with the mandala motif and a marigold glow.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child, this.radius = 28, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: const BoxDecoration(gradient: C.heroGradient),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: MandalaPainter())),
            Positioned(
              right: -60,
              top: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [C.gold400.withValues(alpha: .35), Colors.transparent])),
              ),
            ),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}

/// Ivory background with the faint pink mandala (used behind scrolling pages).
class PatternBg extends StatelessWidget {
  const PatternBg({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: ColoredBox(color: C.ivory, child: CustomPaint(painter: MandalaPainter(color: C.brand600, opacity: .05)))),
        child,
      ]);
}

class ProgressRing extends StatelessWidget {
  const ProgressRing(this.value, {super.key, this.size = 96});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size.square(size), painter: _RingPainter(value.clamp(0, 100) / 100)),
          Text.rich(TextSpan(text: '$value', style: display(size * .26), children: [TextSpan(text: '%', style: display(size * .13))])),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);
  final double v;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(5, 5, s.width - 10, s.height - 10);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = C.sand);
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [C.brand500, C.gold400, C.brand500], transform: GradientRotation(-math.pi / 2)).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v;
}

const _grads = [
  [C.brand400, C.brand700], [C.gold300, C.gold600], [Color(0xFFA78BFA), Color(0xFF6D28D9)],
  [Color(0xFF2DD4BF), Color(0xFF0F766E)], [Color(0xFFFB7185), Color(0xFFBE123C)], [Color(0xFF38BDF8), Color(0xFF0369A1)],
];

/// Photo (blurred + lock when private) or a gradient monogram.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.seed, this.photo, this.locked = false, this.size = 48, this.radius, this.premium = false});
  final String name, seed;
  final String? photo;
  final bool locked, premium;
  final double size;
  final double? radius;
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    final g = _grads[seed.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff) % _grads.length];
    final r = BorderRadius.circular(radius ?? size / 2);
    final url = Config.media(photo);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: r,
          child: url != null
              ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (_, _, _) => _mono(g, initials))
              : _mono(g, initials),
        ),
        if (locked)
          Center(
            child: Container(
              width: math.min(36, size * .4),
              height: math.min(36, size * .4),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.lock_rounded, size: math.min(18, size * .2), color: C.brand700),
            ),
          ),
        if (premium)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.gold300, C.gold500]), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.workspace_premium_rounded, size: 11, color: Colors.white),
            ),
          ),
      ]),
    );
  }

  Widget _mono(List<Color> g, String initials) => Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g)),
        alignment: Alignment.center,
        child: Text(initials, style: display(size * .36, color: Colors.white)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title, text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.brand50, C.gold50]), borderRadius: BorderRadius.circular(24)),
            child: Icon(icon, size: 34, color: C.brand500),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: display(20)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      );
}

/// Loading / error wrapper for a Future.
class Loader<T> extends StatelessWidget {
  const Loader({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T>? future;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (_, s) {
          if (s.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load",
              text: s.error.toString(),
              action: onRetry == null ? null : Btn('Try again', icon: Icons.refresh_rounded, kind: BtnKind.secondary, onPressed: onRetry),
            );
          }
          if (!s.hasData) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: C.brand600)));
          return builder(s.data as T);
        },
      );
}

/// Multi-select chips; empty selection = "Any".
class ChipSelect<T> extends StatelessWidget {
  const ChipSelect({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final List<T> value;
  final ValueChanged<List<T>> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        _chip('Any', value.isEmpty, () => onChanged([])),
        for (final (v, l) in options)
          _chip(l, value.contains(v), () => onChanged(value.contains(v) ? (List.of(value)..remove(v)) : [...value, v])),
      ]);

  Widget _chip(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? C.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? C.brand400 : C.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? C.brand700 : C.ink)),
        ),
      );
}

/// Key/value facts in two columns.
class Facts extends StatelessWidget {
  const Facts(this.items, {super.key});
  final List<(String, String?)> items;
  @override
  Widget build(BuildContext context) {
    final shown = items.where((e) => e.$2 != null && e.$2!.isNotEmpty).toList();
    return LayoutBuilder(builder: (_, c) {
      final w = (c.maxWidth - 16) / 2;
      return Wrap(spacing: 16, runSpacing: 14, children: [
        for (final (k, v) in shown)
          SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: C.muted)),
              const SizedBox(height: 2),
              Text(v!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ]),
          ),
      ]);
    });
  }
}

/// Renders **bold** and *italic* (assistant answers).
class RichBody extends StatelessWidget {
  const RichBody(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|\*[^*\s][^*]*\*)');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final t = m.group(0)!;
      spans.add(t.startsWith('**')
          ? TextSpan(text: t.substring(2, t.length - 2), style: const TextStyle(fontWeight: FontWeight.w700))
          : TextSpan(text: t.substring(1, t.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: style ?? const TextStyle(fontSize: 15, height: 1.45));
  }
}
