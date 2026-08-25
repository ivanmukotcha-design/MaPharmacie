import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static Database? _db;
  static const _version = 1;
  static const _dbName = 'pharmaflow.db';

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE medicaments (
        id TEXT PRIMARY KEY,
        pharmacie_id TEXT NOT NULL,
        nom TEXT NOT NULL,
        categorie TEXT,
        description TEXT,
        prix_grossiste REAL,
        prix_detail REAL,
        fournisseur_id TEXT,
        fournisseur_nom TEXT,
        image_url TEXT,
        date_expiration TEXT,
        code_barres TEXT,
        seuil_alerte INTEGER DEFAULT 10,
        cartons INTEGER DEFAULT 0,
        boites INTEGER DEFAULT 0,
        plaquettes INTEGER DEFAULT 0,
        comprimes INTEGER DEFAULT 0,
        flacons INTEGER DEFAULT 0,
        cartons_par_boite INTEGER DEFAULT 20,
        boites_par_plaquette INTEGER DEFAULT 10,
        plaquettes_par_comprime INTEGER DEFAULT 10,
        est_actif INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        synced INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE ventes (
        id TEXT PRIMARY KEY,
        pharmacie_id TEXT NOT NULL,
        type_vente TEXT,
        total_ht REAL,
        total_ttc REAL,
        benefice REAL,
        date TEXT,
        notes TEXT,
        synced INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE vente_items (
        id TEXT PRIMARY KEY,
        vente_id TEXT NOT NULL,
        medicament_id TEXT,
        medicament_nom TEXT,
        quantite INTEGER,
        unite TEXT,
        prix_unitaire REAL,
        prix_achat REAL,
        sous_total REAL,
        FOREIGN KEY (vente_id) REFERENCES ventes(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE fournisseurs (
        id TEXT PRIMARY KEY,
        pharmacie_id TEXT NOT NULL,
        nom TEXT NOT NULL,
        telephone TEXT,
        email TEXT,
        adresse TEXT,
        notes TEXT,
        created_at TEXT,
        synced INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE activites (
        id TEXT PRIMARY KEY,
        pharmacie_id TEXT NOT NULL,
        type TEXT,
        description TEXT,
        metadata TEXT,
        date TEXT,
        synced INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        collection TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        created_at TEXT,
        attempts INTEGER DEFAULT 0
      )
    ''');

    // Index pour performances
    await db.execute('CREATE INDEX idx_medicaments_pharmacie ON medicaments(pharmacie_id)');
    await db.execute('CREATE INDEX idx_ventes_pharmacie ON ventes(pharmacie_id)');
    await db.execute('CREATE INDEX idx_ventes_date ON ventes(date)');
    await db.execute('CREATE INDEX idx_fournisseurs_pharmacie ON fournisseurs(pharmacie_id)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrations futures
  }

  // ─── MÉDICAMENTS ──────────────────────────────────────────────────────────

  static Future<void> upsertMedicament(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'medicaments',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getMedicaments(String pharmacieId) async {
    final db = await database;
    return db.query(
      'medicaments',
      where: 'pharmacie_id = ? AND est_actif = 1',
      whereArgs: [pharmacieId],
      orderBy: 'nom ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> searchMedicaments(
    String pharmacieId,
    String query,
  ) async {
    final db = await database;
    return db.query(
      'medicaments',
      where: 'pharmacie_id = ? AND est_actif = 1 AND (nom LIKE ? OR code_barres = ?)',
      whereArgs: [pharmacieId, '%$query%', query],
    );
  }

  static Future<void> deleteMedicament(String id) async {
    final db = await database;
    await db.update(
      'medicaments',
      {'est_actif': 0, 'synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── VENTES ───────────────────────────────────────────────────────────────

  static Future<void> insertVente(
    Map<String, dynamic> vente,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('ventes', vente, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final item in items) {
        await txn.insert('vente_items', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<List<Map<String, dynamic>>> getVentes(
    String pharmacieId, {
    DateTime? dateDebut,
    DateTime? dateFin,
  }) async {
    final db = await database;
    String where = 'pharmacie_id = ?';
    List<dynamic> args = [pharmacieId];

    if (dateDebut != null) {
      where += ' AND date >= ?';
      args.add(dateDebut.toIso8601String());
    }
    if (dateFin != null) {
      where += ' AND date <= ?';
      args.add(dateFin.toIso8601String());
    }

    return db.query('ventes', where: where, whereArgs: args, orderBy: 'date DESC');
  }

  static Future<List<Map<String, dynamic>>> getVenteItems(String venteId) async {
    final db = await database;
    return db.query('vente_items', where: 'vente_id = ?', whereArgs: [venteId]);
  }

  // Dashboard stats
  static Future<Map<String, dynamic>> getDashboardStats(String pharmacieId) async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day).toIso8601String();

    final ventesJour = await db.rawQuery(
      'SELECT COALESCE(SUM(total_ttc), 0) as total, COALESCE(SUM(benefice), 0) as benefice, COUNT(*) as count FROM ventes WHERE pharmacie_id = ? AND date >= ?',
      [pharmacieId, startOfDay],
    );

    final stockStats = await db.rawQuery(
      'SELECT COUNT(*) as total FROM medicaments WHERE pharmacie_id = ? AND est_actif = 1',
      [pharmacieId],
    );

    return {
      'ventes_jour': ventesJour.first['total'],
      'benefices_jour': ventesJour.first['benefice'],
      'ventes_count': ventesJour.first['count'],
      'total_medicaments': stockStats.first['total'],
    };
  }

  // ─── SYNC QUEUE ───────────────────────────────────────────────────────────

  static Future<void> addToSyncQueue({
    required String collection,
    required String docId,
    required String operation,
    Map<String, dynamic>? data,
  }) async {
    final db = await database;
    await db.insert('sync_queue', {
      'collection': collection,
      'doc_id': docId,
      'operation': operation,
      'data': data != null ? data.toString() : null,
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await database;
    return db.query(
      'sync_queue',
      where: 'attempts < 5',
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> removeSyncItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> incrementAttempts(int id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sync_queue SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('medicaments');
    await db.delete('ventes');
    await db.delete('vente_items');
    await db.delete('fournisseurs');
    await db.delete('activites');
    await db.delete('sync_queue');
  }
}
