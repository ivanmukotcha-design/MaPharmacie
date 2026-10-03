import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/settings/backup_screen.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/services/backup_service.dart';
import 'package:pharmaflow/services/sync_service.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  _User(this.uid);
}

class _Backup extends BackupService {
  _Backup(super.access);
  int creates = 0;
  int restores = 0;
  late Completer<Uint8List> creation;
  @override
  Future<Uint8List> create(String owner, String password) {
    creates++;
    creation = Completer<Uint8List>();
    return creation.future;
  }

  @override
  Future<void> restore(BackupSnapshot snapshot, String owner) async {
    restores++;
  }
}

class _Files extends Fake implements BackupFiles {
  Uint8List? selected;
  int shares = 0;
  @override
  Future<Uint8List?> pick() async => selected;
  @override
  Future<void> share(
    Uint8List bytes,
    Rect? origin,
    void Function() checkAccess,
  ) async {
    checkAccess();
    shares++;
  }
}

class _Sync extends Fake implements SyncService {
  @override
  Future<void> maintenance(Future<void> Function() action) => action();
  @override
  void scheduleSync() {}
}

void main() {
  late ProviderContainer container;
  late _Backup backup;
  late _Files files;
  final session = StateProvider<User?>((ref) => _User('pharma-1'));

  setUp(() {
    final access = RepositoryAccess((owner, write) {
      if (container.read(session)?.uid != owner) {
        throw StateError('Le compte a changé.');
      }
    });
    backup = _Backup(access);
    files = _Files();
    container = ProviderContainer(
      overrides: [
        pharmacieWritableProvider.overrideWithValue(true),
        currentUserProvider.overrideWith((ref) => ref.watch(session)),
        repositoryAccessProvider.overrideWithValue(access),
        backupServiceProvider.overrideWithValue(backup),
        backupFilesProvider.overrideWithValue(files),
        syncServiceProvider.overrideWithValue(_Sync()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> password(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'ma phrase secrète privée',
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      'ma phrase secrète privée',
    );
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Uint8List emptyBackup({String owner = 'pharma-1'}) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format_version': 1,
        'schema_version': 2,
        'pharmacie_id': owner,
        'exported_at': '2026-09-30T12:00:00',
        'tables': {for (final table in BackupService.tables) table: []},
      }),
    ),
  );

  testWidgets(
    'Annuler ou saisir des phrases différentes ne crée aucune copie',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Créer une sauvegarde chiffrée'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byType(TextFormField).first,
        'ma phrase secrète privée',
      );
      await tester.enterText(find.byType(TextFormField).last, 'différente');
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      expect(
        find.text('Les phrases secrètes ne correspondent pas.'),
        findsOneWidget,
      );
      expect(backup.creates, 0);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(backup.creates, 0);
      expect(files.shares, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'La création empêche les doubles clics et le partage après changement de compte',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Créer une sauvegarde chiffrée'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await password(tester);
      expect(backup.creates, 1);
      await tester.tap(find.text('Créer une sauvegarde chiffrée'));
      expect(backup.creates, 1);
      container.read(session.notifier).state = _User('pharma-2');
      backup.creation.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(files.shares, 0);
      expect(find.text('Le compte a changé.'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'La restauration exige une confirmation et signale les anciens JSON',
    (tester) async {
      await mount(tester);
      files.selected = emptyBackup();
      await tester.scrollUntilVisible(
        find.text('Restaurer une sauvegarde'),
        200,
      );
      await tester.tap(find.text('Restaurer une sauvegarde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.textContaining('ancienne copie JSON non chiffrée'),
        findsOneWidget,
      );
      expect(backup.restores, 0);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(backup.restores, 0);
      await tester.tap(find.text('Restaurer une sauvegarde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Restaurer cette copie'));
      await tester.pumpAndSettle();
      expect(backup.restores, 1);
      expect(
        find.textContaining('Copie restaurée localement.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Une sauvegarde étrangère est refusée avant confirmation', (
    tester,
  ) async {
    await mount(tester);
    files.selected = emptyBackup(owner: 'pharma-2');
    await tester.scrollUntilVisible(find.text('Restaurer une sauvegarde'), 200);
    await tester.tap(find.text('Restaurer une sauvegarde'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('appartient à une autre pharmacie'),
      findsWidgets,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(backup.restores, 0);
    expect(tester.takeException(), isNull);
  });
}
