import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/translate.dart';

/// "Translate to …" under a received message; shows the translation inline.
class TranslateButton extends StatefulWidget {
  const TranslateButton(this.text, {super.key, this.dark = false});
  final String text;
  final bool dark;
  @override
  State<TranslateButton> createState() => _TranslateButtonState();
}

class _TranslateButtonState extends State<TranslateButton> {
  String? _out, _outLang, _err;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: targetLang,
        builder: (_, lang, _) {
          if (!needsTranslation(widget.text, lang)) return const SizedBox.shrink();
          final showing = _out != null && _outLang == lang;
          final fg = widget.dark ? Colors.white.withValues(alpha: .85) : C.brand700;
          final label = languages.firstWhere((l) => l.$1 == lang, orElse: () => (lang, lang)).$2;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showing)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: widget.dark ? Colors.white24 : C.line))),
                child: Text(_out!, style: TextStyle(fontSize: 14, height: 1.4, color: widget.dark ? Colors.white : C.ink)),
              ),
            InkWell(
              onTap: _busy
                  ? null
                  : () async {
                      if (showing) return setState(() => _out = null);
                      setState(() {
                        _busy = true;
                        _err = null;
                      });
                      try {
                        final t = await translateText(widget.text, lang);
                        setState(() {
                          _out = t;
                          _outLang = lang;
                        });
                      } catch (e) {
                        setState(() => _err = e.toString());
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _busy ? SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: fg)) : Icon(Icons.translate_rounded, size: 13, color: fg),
                  const SizedBox(width: 4),
                  Text(showing ? 'Show original' : 'Translate to $label', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
                ]),
              ),
            ),
            if (_err != null) Text(_err!, style: TextStyle(fontSize: 11, color: widget.dark ? Colors.white70 : C.red)),
          ]);
        },
      );
}

/// 🌐 language selector for chat headers.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: targetLang,
        builder: (_, lang, _) => PopupMenuButton<String>(
          tooltip: 'Translate messages to',
          initialValue: lang,
          onSelected: (v) => targetLang.value = v,
          itemBuilder: (_) => [for (final (c, l) in languages) PopupMenuItem(value: c, child: Text(l))],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: light ? Colors.white.withValues(alpha: .15) : C.sand,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: light ? Colors.white24 : C.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.language_rounded, size: 15, color: light ? Colors.white : C.muted),
              const SizedBox(width: 4),
              Text(languages.firstWhere((l) => l.$1 == lang, orElse: () => (lang, lang)).$2,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: light ? Colors.white : C.ink)),
            ]),
          ),
        ),
      );
}
