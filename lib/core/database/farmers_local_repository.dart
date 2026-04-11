import 'package:isar/isar.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/farmer_model.dart';

/// Local-first farmer repository backed by Isar.
/// All reads are instant (no network). Farmers are written once on login.
class FarmersLocalRepository {
  /// Persist a list of farmers from the login API response into Isar.
  /// Upserts by serverId so re-login doesn't create duplicates.
  Future<void> saveFromLogin(List<dynamic> farmers, int routeId) async {
    final isar = await AppDatabase.instance;
    final models = farmers.map((f) {
      final m = f as Map<String, dynamic>;
      final model = FarmerModel()
        ..serverId = (m['id'] as num?)?.toInt()
        ..routeId = routeId
        ..uuid = m['farmer_no']?.toString() ?? ''
        ..farmerCode = m['farmer_no']?.toString() ?? ''
        ..name = m['full_name']?.toString() ?? m['short_name']?.toString() ?? ''
        ..phone = m['phone']?.toString() ?? ''
        ..nationalId = ''
        ..location = ''
        ..county = ''
        ..ward = ''
        ..paymentMethod = ''
        ..mpesaNumber = ''
        ..bankName = ''
        ..bankAccount = ''
        ..totalKgDelivered = 0
        ..totalEarnings = 0
        ..deliveryCount = 0
        ..isActive = (m['status']?.toString() ?? 'active') != 'inactive'
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now()
        ..synced = true;
      return model;
    }).toList();

    await isar.writeTxn(() async {
      // Upsert each farmer: if serverId exists, update; otherwise insert.
      for (final model in models) {
        if (model.serverId != null) {
          final existing = await isar.farmerModels.getByServerId(model.serverId);
          if (existing != null) {
            model.id = existing.id; // keep same Isar ID to update in place
          }
        }
        await isar.farmerModels.put(model);
      }
    });
  }

  /// Return all farmers for a given route, sorted by name.
  Future<List<FarmerModel>> getByRoute(int routeId) async {
    final isar = await AppDatabase.instance;
    return isar.farmerModels
        .where()
        .routeIdEqualTo(routeId)
        .sortByName()
        .findAll();
  }

  /// Return all stored farmers.
  Future<List<FarmerModel>> getAll() async {
    final isar = await AppDatabase.instance;
    return isar.farmerModels.where().findAll();
  }

  /// Count of farmers for a route.
  Future<int> countByRoute(int routeId) async {
    final isar = await AppDatabase.instance;
    return isar.farmerModels.where().routeIdEqualTo(routeId).count();
  }
}
