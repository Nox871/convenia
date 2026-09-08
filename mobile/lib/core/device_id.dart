import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identificador de dispositivo persistente, usado como `owner_ref` de las
/// listas de compra (RF-LIST-*) mientras el proyecto no tenga autenticación
/// real. Se genera una sola vez por instalación y se reutiliza siempre.
class DeviceId {
  DeviceId._();

  static const _prefsKey = 'convenia_device_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }
}
