import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

const _params = SaveDesktopParams(name: 'Mac', host: '192.168.1.2', port: '58682', secure: false, password: 'pw1');

void main() {
  late AppDatabase db;
  late _MockSecureStorage storage;
  late DesktopsLocalDataSourceImp source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _MockSecureStorage();
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    source = DesktopsLocalDataSourceImp(db.desktopDao, storage);
  });

  tearDown(() => db.close());

  test('save stores the row, the password under its id, and activates it', () async {
    final saved = await source.save(_params);

    expect(saved.id, isNotEmpty);
    expect(saved.isActive, isTrue);
    expect(saved.name, 'Mac');
    verify(() => storage.write(key: 'server.password.${saved.id}', value: 'pw1')).called(1);
  });

  test('saving the same endpoint again reuses the id and rotates the password', () async {
    final first = await source.save(_params);
    final second = await source.save(const SaveDesktopParams(
      name: 'Mac', host: '192.168.1.2', port: '58682', secure: false, password: 'pw2',
    ));

    expect(second.id, first.id);
    expect(await source.watchAll().first, hasLength(1));
    verify(() => storage.write(key: 'server.password.${first.id}', value: 'pw2')).called(1);
  });

  test('passwordFor reads the keychain entry for that id', () async {
    when(() => storage.read(key: 'server.password.x')).thenAnswer((_) async => 'pw');
    expect(await source.passwordFor('x'), 'pw');
  });

  test('remove deletes the row and its password', () async {
    final saved = await source.save(_params);
    await source.remove(saved.id!);

    expect(await source.watchAll().first, isEmpty);
    verify(() => storage.delete(key: 'server.password.${saved.id}')).called(1);
  });

  test('deactivate leaves no active desktop; activate picks one', () async {
    final saved = await source.save(_params);
    await source.deactivate();
    expect(await source.getActive(), isNull);
    await source.activate(saved.id!);
    expect((await source.getActive())?.id, saved.id);
  });

  test('activate with a name refreshes the label unless the user renamed it', () async {
    final saved = await source.save(_params);
    await source.activate(saved.id!, name: 'New');
    expect((await source.getActive())?.name, 'New');

    await source.rename(RenameDesktopParams(id: saved.id!, name: 'Mine'));
    await source.activate(saved.id!, name: 'Newer');
    expect((await source.getActive())?.name, 'Mine');
  });

  test('activate ignores a blank name', () async {
    final saved = await source.save(_params);
    await source.activate(saved.id!, name: '  ');
    expect((await source.getActive())?.name, 'Mac');
  });

  test('a keychain write failure surfaces as LocalFailure', () async {
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async => throw PlatformException(code: 'keychain'));
    await expectLater(source.save(_params), throwsA(isA<LocalFailure<void>>()));
  });

  test('a keychain read failure surfaces as LocalFailure', () async {
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => throw PlatformException(code: 'keychain'));
    await expectLater(source.passwordFor('x'), throwsA(isA<LocalFailure<void>>()));
  });

  test('a keychain delete failure surfaces as LocalFailure', () async {
    final saved = await source.save(_params);
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async => throw PlatformException(code: 'keychain'));
    await expectLater(source.remove(saved.id!), throwsA(isA<LocalFailure<void>>()));
  });

  test('rename changes the label', () async {
    final saved = await source.save(_params);
    await source.rename(RenameDesktopParams(id: saved.id!, name: 'Studio'));
    expect((await source.watchAll().first).single.name, 'Studio');
  });
}
