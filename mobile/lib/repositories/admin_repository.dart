import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../services/api_client.dart';

/// Acciones que sólo puede hacer un administrador.
class AdminRepository {
  final ApiClient _client;

  AdminRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// Descarga el historial de precios en CSV y lo guarda en un archivo
  /// temporal; devuelve su ruta. `supermarket` en `null` = todos.
  Future<String> downloadPriceHistoryCsv({String? supermarket, required int days}) async {
    final file = await _client.getFile(
      '/api/v1/admin/exports/price-history',
      queryParameters: {'days': '$days', if (supermarket != null) 'supermarket': supermarket},
    );
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}${Platform.pathSeparator}${file.filename}';
    await File(path).writeAsBytes(file.bytes, flush: true);
    return path;
  }
}
