import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../repositories/assistant_repository.dart';

class _Message {
  final String text;
  final bool fromUser;
  final bool isError;

  const _Message(this.text, {required this.fromUser, this.isError = false});
}

/// Chat con ConveniaBot, el agente de IA (n8n + Gemini) que responde sobre Convenia
/// y consulta la API de precios. Si el agente no está disponible, la pantalla lo dice
/// y el resto de la aplicación sigue funcionando.
class AssistantScreen extends StatefulWidget {
  final AssistantRepository? repository;

  const AssistantScreen({super.key, this.repository});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantRepository _repository = widget.repository ?? AssistantRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [
    const _Message(
      'Hola, soy ConveniaBot. Te ayudo a comparar precios de supermercados y a usar la aplicación.',
      fromUser: false,
    ),
  ];
  bool _waiting = false;
  String? _lastQuestion;

  static const _suggestions = [
    '¿Cuánto cuesta la leche?',
    '¿Cómo armo una lista con presupuesto?',
    '¿Repartir la compra ahorra siempre?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _waiting) return;
    _input.clear();
    setState(() {
      _messages.add(_Message(text, fromUser: true));
      _waiting = true;
      _lastQuestion = text;
    });
    _scrollToEnd();
    try {
      final answer = await _repository.ask(text);
      if (!mounted) return;
      setState(() => _messages.add(_Message(answer, fromUser: false)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Message('${e.message} Intenta de nuevo en un momento.', fromUser: false, isError: true)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.add(const _Message('No pude hablar con el asistente. Intenta de nuevo.', fromUser: false, isError: true)));
    } finally {
      if (mounted) setState(() => _waiting = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softIvory,
      appBar: AppBar(
        backgroundColor: AppColors.softIvory,
        elevation: 0,
        title: Text('ConveniaBot', style: AppText.screenTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              key: const Key('assistant_list'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                for (final m in _messages) _Bubble(message: m),
                if (_messages.length == 1) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _suggestions)
                        ActionChip(
                          key: Key('assistant_suggestion_${_suggestions.indexOf(s)}'),
                          label: Text(s),
                          backgroundColor: AppColors.lavenderMist,
                          onPressed: () => _send(s),
                        ),
                    ],
                  ),
                ],
                if (_waiting)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      key: const Key('assistant_typing'),
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text('ConveniaBot está escribiendo…', style: AppText.caption.copyWith(color: AppColors.inkMuted)),
                      ],
                    ),
                  ),
                if (!_waiting && _messages.isNotEmpty && _messages.last.isError && _lastQuestion != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('assistant_retry'),
                      onPressed: () => _send(_lastQuestion!),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('assistant_input'),
                      controller: _input,
                      enabled: !_waiting,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Escribe tu pregunta',
                        filled: true,
                        fillColor: AppColors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('assistant_send'),
                    style: IconButton.styleFrom(backgroundColor: AppColors.brandIndigo),
                    onPressed: _waiting ? null : () => _send(_input.text),
                    icon: const Icon(Icons.arrow_upward_rounded, color: AppColors.white),
                    tooltip: 'Enviar',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Message message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    final color = user
        ? AppColors.brandIndigo
        : (message.isError ? AppColors.errorSurface : AppColors.white);
    final textColor = user ? AppColors.white : AppColors.ink;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: user ? null : Border.all(color: AppColors.mist),
        ),
        child: SelectableText(message.text, style: AppText.body.copyWith(color: textColor, height: 1.35)),
      ),
    );
  }
}
