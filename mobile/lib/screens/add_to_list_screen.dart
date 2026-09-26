import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/formatters.dart';
import '../core/ocr_list_cleaner.dart';
import '../core/spoken_list_parser.dart';
import '../core/suggested_lists.dart';
import '../core/theme.dart';
import '../models/product_suggestion.dart';
import '../repositories/product_repository.dart';
import '../state/preferences_controller.dart';
import '../widgets/product_image.dart';
import '../widgets/scope_note.dart';

/// Un renglón de la revisión: lo que se entendió, las opciones del
/// catálogo (la primera es la propuesta) y cuál quedó elegida.
class _ReviewRow {
  final String heardAs;
  final List<ProductSuggestion> options;
  int selectedIndex = 0;
  int quantity;
  bool included;
  bool showingOptions = false;

  _ReviewRow({required this.heardAs, required this.options, required this.quantity})
    : included = options.isNotEmpty;

  ProductSuggestion? get chosen => options.isEmpty ? null : options[selectedIndex];
}

/// Única entrada para agregar productos a una lista: se escribe, se dice o
/// se fotografía lo que se necesita, con el lenguaje de todos los días
/// ("arroz, leche, huevos"). Todo pasa por la misma revisión: para cada
/// término la app propone el producto más comparable (el que más
/// supermercados venden), y la persona puede cambiarlo, ajustar la
/// cantidad o descartarlo antes de agregar. Nada se agrega sin confirmar.
///
/// Devuelve, con `Navigator.pop`, la lista de (id de producto, cantidad).
class AddToListScreen extends StatefulWidget {
  const AddToListScreen({super.key});

  @override
  State<AddToListScreen> createState() => _AddToListScreenState();
}

class _AddToListScreenState extends State<AddToListScreen> {
  final _repository = ProductRepository();
  final _controller = TextEditingController();
  final _speech = SpeechToText();
  final _picker = ImagePicker();
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  bool _speechAvailable = false;
  String? _speechLocaleId;
  bool _listening = false;
  bool _busy = false;
  String? _message;
  List<_ReviewRow>? _rows;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(onError: _onSpeechError, onStatus: _onSpeechStatus);
    String? locale;
    if (available) {
      // Español de Colombia si el teléfono lo tiene; si no, cualquier español.
      final locales = await _speech.locales();
      String norm(String id) => id.replaceAll('-', '_').toLowerCase();
      final exact = locales.where((l) => norm(l.localeId) == 'es_co');
      final anySpanish = locales.where((l) => norm(l.localeId).startsWith('es'));
      locale = exact.isNotEmpty
          ? exact.first.localeId
          : (anySpanish.isNotEmpty ? anySpanish.first.localeId : null);
    }
    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _speechLocaleId = locale;
      });
    }
  }

  /// El reconocedor terminó (por silencio o por tiempo): el botón deja de
  /// mostrarse como "escuchando" aunque no haya llegado un resultado final.
  void _onSpeechStatus(String status) {
    if ((status == 'done' || status == 'notListening') && mounted && _listening) {
      setState(() => _listening = false);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _message = switch (error.errorMsg) {
        'error_no_match' => 'No te entendimos bien. Toca el micrófono e inténtalo de nuevo.',
        'error_speech_timeout' => 'No escuchamos nada. Toca el micrófono y habla.',
        'error_permission' => 'Falta el permiso de micrófono. Actívalo en los ajustes del teléfono.',
        'error_network' || 'error_network_timeout' =>
          'El reconocimiento de voz necesita internet. Revisa tu conexión o escribe la lista.',
        _ => 'No pudimos usar la voz (${error.errorMsg}). Puedes escribir la lista.',
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _search() async {
    final entries = parseSpokenList(_controller.text);
    FocusScope.of(context).unfocus();

    if (entries.isEmpty) {
      setState(() {
        _rows = null;
        _message = 'Escribe o di lo que necesitas, por ejemplo: arroz, leche, huevos.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    final prefer = context.read<PreferencesController>().suggestion.apiValue;
    final rows = await Future.wait(entries.map((entry) async {
      try {
        final response = await _repository.suggestProducts(entry.searchText, limit: 4, prefer: prefer);
        return _ReviewRow(
          heardAs: entry.searchText,
          options: response.suggestions,
          quantity: entry.quantity,
        );
      } catch (_) {
        return _ReviewRow(heardAs: entry.searchText, options: const [], quantity: entry.quantity);
      }
    }));

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _busy = false;
    });
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechAvailable) {
      setState(
        () => _message = 'No pudimos activar la voz. Revisa el permiso de micrófono en los ajustes y que '
            'el teléfono tenga el servicio de voz de Google. Mientras tanto, escribe la lista.',
      );
      return;
    }

    setState(() {
      _listening = true;
      _message = null;
    });

    await _speech.listen(
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _search();
        }
      },
      // Una frase con varios productos es más larga que una palabra: sin
      // esto el reconocimiento corta antes de que la persona termine.
      listenOptions: SpeechListenOptions(
        localeId: _speechLocaleId,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );
  }

  Future<void> _scanPhoto(ImageSource source) async {
    final photo = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (photo == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final recognized = await _textRecognizer.processImage(InputImage.fromFilePath(photo.path));
      final lines = cleanOcrLines(recognized.text);

      if (lines.isEmpty) {
        setState(() {
          _busy = false;
          _message = 'No se detectó texto legible. Prueba con letra clara y buena luz.';
        });
        return;
      }

      // Se muestra lo leído en el campo, para que la persona lo corrija antes
      // de buscar: el OCR nunca decide solo.
      _controller.text = lines.join('\n');
      await _search();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'No pudimos leer la imagen. Intenta de nuevo.';
        });
      }
    }
  }

  void _pickPhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _scanPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _scanPhoto(ImageSource.gallery);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: Text(
                'Funciona mejor con letra clara y un producto por línea.',
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    final result = _rows!
        .where((r) => r.included && r.chosen != null)
        .map((r) => MapEntry(r.chosen!.id, r.quantity))
        .toList();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selected = rows?.where((r) => r.included && r.chosen != null).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text('Agregar a la lista', style: AppText.screenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.horizontalPage),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: _listening ? 'Escuchando...' : 'Ej.: arroz, leche, huevos, aguacate',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Decir la lista',
                        icon: Icon(
                          _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                          color: _listening ? AppColors.brandIndigo : AppColors.inkMuted,
                        ),
                        onPressed: _toggleListening,
                      ),
                      IconButton(
                        tooltip: 'Foto de una lista',
                        icon: const Icon(Icons.photo_camera_outlined, color: AppColors.inkMuted),
                        onPressed: _pickPhotoSource,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
              child: ElevatedButton(
                onPressed: _busy ? null : _search,
                child: const Text('Buscar productos'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const ScopeNote(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.horizontalPage),
                child: Text(_message!, style: AppText.body),
              ),
            if (!_busy && rows == null)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.horizontalPage),
                  children: [
                    Text('LISTAS SUGERIDAS', style: AppText.caption),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Punto de partida: revisas los productos y quitas o cambias lo que quieras.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final list in suggestedLists)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ListTile(
                          title: Text(list.name, style: AppText.productName),
                          subtitle: Text('${list.description} · ${list.terms.length} productos', style: AppText.caption),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            _controller.text = list.asText;
                            _search();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            if (!_busy && rows != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.horizontalPage,
                  AppSpacing.lg,
                  AppSpacing.horizontalPage,
                  AppSpacing.xs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Propusimos el producto que más supermercados venden. '
                    'Cámbialo, ajusta la cantidad o quítalo.',
                    style: AppText.caption,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _RowTile(
                    row: rows[index],
                    onChanged: () => setState(() {}),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.horizontalPage),
                child: ElevatedButton(
                  onPressed: selected > 0 ? _confirm : null,
                  child: Text('Agregar $selected producto${selected == 1 ? '' : 's'}'),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final _ReviewRow row;
  final VoidCallback onChanged;

  const _RowTile({required this.row, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chosen = row.chosen;

    if (chosen == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: false,
        leading: const Icon(Icons.help_outline_rounded, color: AppColors.inkFaint),
        title: Text('"${row.heardAs}"'),
        subtitle: const Text('No encontramos este producto en el catálogo'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Checkbox(
                value: row.included,
                onChanged: (v) {
                  row.included = v ?? false;
                  onChanged();
                },
              ),
              ProductImage(imageUrl: chosen.imageUrl, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chosen.name, style: AppText.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      '${chosen.price != null ? 'Desde ${formatCop(chosen.price!)}' : 'Sin precio'}'
                      ' · ${chosen.offersCount} ${chosen.offersCount == 1 ? 'supermercado' : 'supermercados'}',
                      style: AppText.caption,
                    ),
                    if (row.options.length > 1)
                      GestureDetector(
                        onTap: () {
                          row.showingOptions = !row.showingOptions;
                          onChanged();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            row.showingOptions ? 'Ocultar opciones' : 'Cambiar por otra opción',
                            style: AppText.caption.copyWith(color: AppColors.brandIndigo),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _Stepper(
                quantity: row.quantity,
                onChanged: (q) {
                  row.quantity = q;
                  onChanged();
                },
              ),
            ],
          ),
        ),
        if (row.showingOptions)
          for (var i = 0; i < row.options.length; i++)
            ListTile(
              dense: true,
              leading: Icon(
                i == row.selectedIndex ? Icons.radio_button_checked : Icons.radio_button_off,
                color: i == row.selectedIndex ? AppColors.brandIndigo : AppColors.inkFaint,
              ),
              onTap: () {
                row.selectedIndex = i;
                row.showingOptions = false;
                onChanged();
              },
              title: Text(row.options[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${row.options[i].price != null ? formatCop(row.options[i].price!) : 'Sin precio'}'
                ' · ${row.options[i].offersCount} ${row.options[i].offersCount == 1 ? 'supermercado' : 'supermercados'}',
              ),
            ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        Text('$quantity', style: AppText.productName),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}
