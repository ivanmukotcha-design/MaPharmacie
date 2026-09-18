import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/local_database/sync_codec.dart';
import 'package:pharmaflow/core/utils/validators.dart';
import 'fixtures.dart';

void main() {
  test('Un tarif de gros absent reste absent en SQL et Firestore', () {
    final med = medicament(prixGrossiste: null);
    med.validate();
    expect(MedicamentModel.fromSql(med.toSql()).prixGrossiste, isNull);
    expect(MedicamentModel.fromMap(med.toMap(), med.id).prixGrossiste, isNull);
    expect(med.prixPourUnite('boite', gros: false), 100);
    expect(() => med.prixPourUnite('boite', gros: true), throwsStateError);
    expect(
      () => medicament(prixGrossiste: -1).validate(),
      throwsFormatException,
    );
  });
  test('Activation des tarifs de gros conservée dans le profil', () {
    final profile = pharmacie(tarifsGrosActifs: true);
    expect(
      PharmacieModel.fromMap(profile.toMap(), profile.id).tarifsGrosActifs,
      isTrue,
    );
  });
  test('SQLite conserve identifiants, booléens, dates, prix et unités', () {
    final med = medicament(expiration: DateTime(2030, 3, 1));
    final restored = MedicamentModel.fromSql(med.toSql());
    expect(restored.toMap(), med.toMap());
    expect(restored.id, med.id);
    final archived = med.copyWith(estActif: false);
    expect(MedicamentModel.fromSql(archived.toSql()).estActif, isFalse);
  });

  test('Vente SQL sépare les articles et restitue la date', () {
    final sale = vente();
    expect(sale.toSql().containsKey('items'), isFalse);
    expect(sale.toSql()['id'], sale.id);
    final restored = VenteModel.fromSql(
      sale.toSql(),
      sale.items.map((item) => item.toMap()).toList(),
    );
    expect(restored.toMap(), sale.toMap());
  });

  test('Vendre un flacon ne crée aucun comprimé', () {
    final remaining = const UnitesStock(flacons: 10).deduire(1, 'flacon');
    expect(remaining.flacons, 9);
    expect(remaining.totalComprimes, 0);
    expect(remaining.totalUniteBase, 9);
  });

  test('Déduction exacte entre conditionnements', () {
    const stock = UnitesStock(
      cartons: 1,
      boites: 2,
      plaquettes: 3,
      comprimes: 4,
    );
    expect(
      stock.deduire(1, 'boite').totalComprimes,
      stock.totalComprimes - 100,
    );
    expect(
      stock.deduire(2, 'plaquette').totalComprimes,
      stock.totalComprimes - 20,
    );
  });

  test(
    'Stock insuffisant, ratios nuls, unités inconnues et mélanges refusés',
    () {
      expect(
        () => const UnitesStock(boites: 1).deduire(2, 'boite'),
        throwsStateError,
      );
      expect(
        () => const UnitesStock(boites: 1).deduire(0, 'boite'),
        throwsFormatException,
      );
      expect(
        () => const UnitesStock(cartonsParBoite: 0).deduire(1, 'boite'),
        throwsFormatException,
      );
      expect(
        () => const UnitesStock(boites: 1).deduire(1, 'inconnue'),
        throwsFormatException,
      );
      expect(
        () => const UnitesStock(boites: 1, flacons: 1).validate(),
        throwsFormatException,
      );
      expect(
        () => const UnitesStock(flacons: 10).deduire(1, 'comprimes'),
        throwsStateError,
      );
    },
  );

  test('Prix et coût sont convertis dans la même unité', () {
    final med = medicament();
    expect(med.prixPourUnite('plaquette', gros: false), 10);
    expect(med.prixPourUnite('boite', gros: true), 80);
    expect(med.coutPourUnite('plaquette'), 5);
    expect(
      () => med.prixPourUnite('flacon', gros: false),
      throwsFormatException,
    );
    expect(
      () => medicament(prixAchat: null).coutPourUnite('boite'),
      throwsStateError,
    );
  });

  test('La file JSON préserve les timestamps et les valeurs imbriquées', () {
    final data = {
      'date': Timestamp(100, 123456789),
      'items': [
        {
          'nom': 'Produit, {test}: "é"',
          'actif': false,
          'prix': 12.5,
          'vide': null,
        },
      ],
    };
    expect(SyncCodec.decode(SyncCodec.encode(data)), data);
    expect(
      () => SyncCodec.decode('{nom: ancien format}'),
      throwsFormatException,
    );
  });

  test('Validation numérique française et valeurs non finies', () {
    expect(parseDecimal(' 12,50 '), 12.5);
    expect(validatePrice('NaN'), isNotNull);
    expect(validatePrice('Infinity'), isNotNull);
    expect(validatePrice('-1'), isNotNull);
    expect(validateQuantity('0', positive: true), isNotNull);
    expect(validateQuantity('1.5'), isNotNull);
  });
}
