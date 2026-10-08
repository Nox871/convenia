import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/device_id.dart';
import '../models/shopping_list.dart';
import '../repositories/shopping_list_repository.dart';
import 'view_status.dart';

/// Estado de la pantalla "Listas": las de la cuenta si hay sesión iniciada; si
/// no, las del dispositivo.
class ShoppingListsController extends ChangeNotifier {
  final ShoppingListRepository _repository;

  ShoppingListsController({ShoppingListRepository? repository, int? accountId, Listenable? refreshSignal})
    : _repository = repository ?? ShoppingListRepository(),
      _accountId = accountId,
      _refreshSignal = refreshSignal {
    _refreshSignal?.addListener(refresh);
    _load();
  }

  final Listenable? _refreshSignal;

  @override
  void dispose() {
    _refreshSignal?.removeListener(refresh);
    super.dispose();
  }

  /// Cuenta cuyas listas se muestran (`null` = invitado, listas del dispositivo).
  int? _accountId;

  /// Al iniciar o cerrar sesión, las listas visibles cambian: se recargan.
  void onAccountChanged(int? accountId) {
    if (accountId == _accountId) return;
    _accountId = accountId;
    // Puede llegar durante la construcción de un widget.
    scheduleMicrotask(_load);
  }

  ViewStatus status = ViewStatus.loading;
  String? errorMessage;
  List<ShoppingListSummary> lists = [];
  bool isCreating = false;

  Future<void> retry() => _load();

  /// Vuelve a pedir las listas SIN mostrar la rueda de carga: se usa al volver
  /// de una lista o al abrir la pestaña, para que los conteos no queden viejos
  /// (agregabas productos y Mis listas seguía diciendo "0 productos").
  Future<void> refresh() async {
    try {
      final ownerRef = await DeviceId.get();
      final result = await _repository.listLists(ownerRef);
      lists = result;
      status = result.isEmpty ? ViewStatus.empty : ViewStatus.loaded;
      notifyListeners();
    } on ApiException {
      // Se conserva lo que ya se mostraba.
    }
  }

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final ownerRef = await DeviceId.get();
      final result = await _repository.listLists(ownerRef);
      lists = result;
      status = result.isEmpty ? ViewStatus.empty : ViewStatus.loaded;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }

  /// Elimina una lista (y sus productos) y recarga las que quedan.
  Future<bool> deleteList(int listId) async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.deleteList(listId, ownerRef);
      await refresh();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Devuelve el id de la lista creada, o null si falló (el error queda en
  /// `errorMessage` para que la UI lo muestre con un snackbar/diálogo).
  Future<int?> createList(String name) async {
    isCreating = true;
    notifyListeners();

    int? createdId;
    try {
      final ownerRef = await DeviceId.get();
      final created = await _repository.createList(ownerRef, name);
      createdId = created.id;
      await _load();
    } on ApiException catch (e) {
      errorMessage = e.message;
    }

    isCreating = false;
    notifyListeners();
    return createdId;
  }
}
