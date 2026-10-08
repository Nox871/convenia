import 'dart:async';

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
import '../models/basket.dart';
import '../models/product_suggestion.dart';
import '../repositories/product_repository.dart';
import '../state/preferences_controller.dart';
import '../widgets/budget_sheet.dart';
import '../widgets/product_image.dart';
import '../widgets/product_picker_sheet.dart';

/// Un renglón de la revisión: lo que se entendió, las opciones del
/// catálogo (la primera es la propuesta) y cuál quedó elegida.
class _ReviewRow {
  final String heardAs;
  List<ProductSuggestion> options;
  int selectedIndex = 0;
  int quantity;
  bool included;

  /// La búsqueda falló (red o servidor): NO es lo mismo que "no existe".
  bool failed;

  /// La lista armada con presupuesto lo dejó fuera por no caber.
  final bool droppedByBudget;

  _ReviewRow({
    required this.heardAs,
    required this.options,
    required this.quantity,
    this.failed = false,
    this.droppedByBudget = false,
  }) : included = options.isNotEmpty;

  ProductSuggestion? get chosen => options.isEmpty ? null : options[selectedIndex];

  /// Pone [item] como el producto elegido de esta fila.
  void choose(ProductSuggestion item) {
    options = [item, ...options.where((o) => o.id != item.id)];
    selectedIndex = 0;
    included = true;
    failed = false;
  }
}

/// Única entrada para agregar productos a una lista: se escribe, se dice o
/// se fotografía lo que se necesita, con el lenguaje de todos los días
/// ("arroz, leche, huevos"). Todo pasa por la misma revisión: para cada
/// término la app propone el producto más comparable (el que más
/// supermercados venden), y la persona puede cambiarlo, ajustar la
/// cantidad o descartarlo antes de agregar. Nada se agrega sin confirmar.
///
/// Devuelve, con `Navigator.pop`, un [AddToListResult] (productos y cantidades).
/// Lo que devuelve la pantalla: los productos elegidos y, si la lista salió de una
/// lista sugerida con presupuesto, ese presupuesto (para guardarlo en la lista).
class AddToListResult {
  final List<MapEntry<String, int>> entries;
  final int? budget;
  const AddToListResult(this.entries, {this.budget});
}

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

  Timer? _silenceTimer;
  bool _voiceSearchPending = false; // hay voz por buscar (evita buscar dos veces)
  bool _speechAvailable = false;
  String? _speechLocaleId;
  bool _listening = false;
  bool _busy = false;
  String _busyText = 'Buscando tus productos…';
  String? _message;
  List<_ReviewRow>? _rows;
  double? _chosenBudget; // presupuesto elegido al armar una lista sugerida
  BasketResponse? _basket; // si la lista salió de una lista sugerida con presupuesto

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
      // El reconocedor se cerró solo: si se alcanzó a oír algo, se busca.
      _searchAfterVoice();
    }
  }

  /// Apaga el micrófono y busca lo dicho, una sola vez por cada vez que se habla.
  void _searchAfterVoice() {
    _silenceTimer?.cancel();
    if (!_voiceSearchPending || !mounted) return;
    _voiceSearchPending = false;
    if (_controller.text.trim().isNotEmpty) _search();
  }

  /// 3 segundos sin oír nada nuevo = terminó de hablar: se apaga el micrófono y se busca.
  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 3), () async {
      if (!_listening || !mounted) return;
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      _searchAfterVoice();
    });
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
    _silenceTimer?.cancel();
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
      _busyText = 'Buscando tus productos en los supermercados…';
      _message = null;
      _basket = null;
    });

    final prefer = context.read<PreferencesController>().suggestion.apiValue;
    final rows = await Future.wait(entries.map((entry) => _lookup(entry, prefer)));

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _busy = false;
    });
  }

  Future<_ReviewRow> _lookup(SpokenListEntry entry, String prefer) async {
    try {
      final response = await _repository.suggestProducts(entry.searchText, limit: 4, prefer: prefer);
      return _ReviewRow(heardAs: entry.searchText, options: response.suggestions, quantity: entry.quantity);
    } catch (_) {
      // Un fallo de red no es "producto inexistente": se marca para reintentar.
      return _ReviewRow(heardAs: entry.searchText, options: const [], quantity: entry.quantity, failed: true);
    }
  }

  Future<void> _retryRow(_ReviewRow row) async {
    final prefer = context.read<PreferencesController>().suggestion.apiValue;
    final again = await _lookup(SpokenListEntry(quantity: row.quantity, searchText: row.heardAs), prefer);
    if (!mounted) return;
    setState(() {
      row.options = again.options;
      row.selectedIndex = 0;
      row.failed = again.failed;
      row.included = again.options.isNotEmpty;
    });
  }

  /// Lista sugerida: pregunta presupuesto y nivel, y arma productos reales.
  Future<void> _buildSuggested(SuggestedList list) async {
    final choice = await showBudgetSheet(context, listName: list.name, productCount: list.terms.length);
    if (choice == null || !mounted) return;
    _chosenBudget = choice.budget;

    _controller.text = list.asText;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _busyText = 'Armando "${list.name}" con los mejores precios para tu presupuesto…';
      _message = null;
      _basket = null;
    });
    try {
      final basket = await _repository.buildBasket(list.terms, tier: choice.tier, budget: choice.budget);
      if (!mounted) return;
      final rows = <_ReviewRow>[
        for (final line in basket.items)
          if (line.found && line.product != null)
            _ReviewRow(
              heardAs: line.term,
              options: [ProductSuggestion.fromListItem(line.product!)],
              quantity: line.quantity,
            )
          else
            _ReviewRow(heardAs: line.term, options: const [], quantity: 1),
        for (final term in basket.droppedTerms)
          _ReviewRow(heardAs: term, options: const [], quantity: 1, droppedByBudget: true),
      ];
      setState(() {
        _rows = rows;
        _basket = basket;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'No pudimos armar la lista. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  /// Total estimado con el mejor precio de cada producto elegido.
  double get _estimatedTotal => (_rows ?? const <_ReviewRow>[])
      .where((r) => r.included && r.chosen?.price != null)
      .fold(0.0, (sum, r) => sum + r.chosen!.price! * r.quantity);

  Future<void> _toggleListening() async {
    if (_listening) {
      // Tocar de nuevo el micrófono = terminé: se apaga y se busca lo dicho.
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      _searchAfterVoice();
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
    _voiceSearchPending = true;
    _armSilenceTimer(); // por si nunca llega a oír nada

    await _speech.listen(
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _searchAfterVoice();
        } else {
          _armSilenceTimer(); // cada palabra nueva reinicia la cuenta de 3 s
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
    Navigator.of(context).pop(AddToListResult(result, budget: _basket != null ? _chosenBudget?.round() : null));
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
            // Una sola tarjeta: la lista se escribe (o se dice, o se fotografía) y se
            // busca desde la misma tarjeta, sin un botón enorme aparte.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.horizontalPage,
                AppSpacing.md,
                AppSpacing.horizontalPage,
                0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.mist),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _controller,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Escuchando…'
                            : 'Escribe tu lista, por ejemplo: arroz, leche y huevos',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.mist),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
                      child: Row(
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
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _busy ? null : _search,
                            icon: const Icon(Icons.search_rounded, size: 20),
                            label: const Text('Buscar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                          onTap: () => _buildSuggested(list),
                        ),
                      ),
                  ],
                ),
              ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.lg),
                    Text(_busyText, style: AppText.body, textAlign: TextAlign.center),
                  ],
                ),
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
                    _basket != null
                        ? 'Elegimos estos productos para tu presupuesto. Cambia cualquiera, '
                            'ajusta la cantidad o quítalo.'
                        : 'Propusimos el producto que más supermercados venden. '
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
                    onRetry: () => _retryRow(rows[index]),
                  ),
                ),
              ),
              if (selected > 0) _TotalBar(total: _estimatedTotal, basket: _basket),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.horizontalPage,
                  AppSpacing.sm,
                  AppSpacing.horizontalPage,
                  AppSpacing.horizontalPage,
                ),
                child: ElevatedButton(
                  onPressed: selected > 0 ? _confirm : null,
                  child: Text('Agregar $selected producto${selected == 1 ? '' : 's'}'),
                ),
              ),
            ] else if (_busy)
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
  final VoidCallback onRetry;

  const _RowTile({required this.row, required this.onChanged, required this.onRetry});

  /// Abre el buscador completo con lo que se pidió, para elegir cualquier
  /// producto (no sólo las pocas sugerencias).
  Future<void> _pick(BuildContext context) async {
    final item = await showProductPicker(context, initialQuery: row.heardAs);
    if (item == null) return;
    row.choose(ProductSuggestion.fromListItem(item));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = row.chosen;

    if (chosen == null) {
      final String detail;
      final IconData icon;
      final String action;
      final VoidCallback onAction;
      if (row.failed) {
        icon = Icons.wifi_off_rounded;
        detail = 'No pudimos buscarlo (revisa tu conexión)';
        action = 'Reintentar';
        onAction = onRetry;
      } else if (row.droppedByBudget) {
        icon = Icons.savings_outlined;
        detail = 'No alcanzó en tu presupuesto';
        action = 'Buscar igual';
        onAction = () => _pick(context);
      } else {
        icon = Icons.help_outline_rounded;
        detail = 'No encontramos este producto en el catálogo';
        action = 'Buscar a mano';
        onAction = () => _pick(context);
      }
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: row.failed ? AppColors.error : AppColors.inkFaint),
        title: Text('"${row.heardAs}"'),
        subtitle: Text(detail),
        trailing: TextButton(onPressed: onAction, child: Text(action)),
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
                    GestureDetector(
                      onTap: () => _pick(context),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Cambiar por otra opción',
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


/// Total estimado de lo elegido (mejor precio de cada producto) y, si la lista
/// se armó con un presupuesto, cuánto sobra o cuánto se pasa.
class _TotalBar extends StatelessWidget {
  final double total;
  final BasketResponse? basket;

  const _TotalBar({required this.total, required this.basket});

  @override
  Widget build(BuildContext context) {
    final budget = basket?.budget;
    final diff = budget == null ? null : budget - total;
    final over = diff != null && diff < 0;
    final tier = basket == null
        ? null
        : (basket!.tierUsed == 'mixto' ? 'Nivel mixto' : 'Nivel ${SpendTier.fromApi(basket!.tierUsed).label.toLowerCase()}');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: over ? AppColors.errorSurface : AppColors.lavenderMist,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimado desde ${formatCop(total)}', style: AppText.productName),
                if (tier != null) Text(tier, style: AppText.caption),
              ],
            ),
          ),
          if (diff != null)
            Text(
              over ? 'Te pasas ${formatCop(-diff)}' : 'Te sobran ${formatCop(diff)}',
              style: AppText.body.copyWith(
                color: over ? AppColors.error : AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
