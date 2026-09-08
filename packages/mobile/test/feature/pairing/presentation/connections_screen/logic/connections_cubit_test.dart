import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';

void main() {
  group('ConnectionsCubit', () {
    test('starts with the dummy saved connections', () {
      final cubit = ConnectionsCubit();
      expect(cubit.connections, hasLength(2));
      expect(cubit.connections.first.name, "Alex's MacBook Pro");
      expect(cubit.connections.first.address, '100.94.12.3');
      cubit.close();
    });

    blocTest<ConnectionsCubit, ConnectionsState>(
      'connectTo marks the row connecting then succeeds after the delay',
      build: ConnectionsCubit.new,
      act: (cubit) {
        fakeAsync((async) {
          cubit.connectTo('alex-macbook-pro');
          expect(cubit.connectingId, 'alex-macbook-pro');
          async.elapse(const Duration(milliseconds: 900));
          expect(cubit.connectingId, isNull);
        });
      },
      expect: () => [const ConnectLoadingState('alex-macbook-pro'), const ConnectSuccessState('alex-macbook-pro')],
    );

    blocTest<ConnectionsCubit, ConnectionsState>(
      'addConnection appends a new entry',
      build: ConnectionsCubit.new,
      act: (cubit) => cubit.addConnection(name: 'Studio iMac', address: '192.168.1.42'),
      expect: () => [const AddConnectionSuccessState()],
      verify: (cubit) {
        expect(cubit.connections, hasLength(3));
        expect(cubit.connections.last.name, 'Studio iMac');
        expect(cubit.connections.last.address, '192.168.1.42');
        expect(cubit.connections.last.lastConnectedLabel, isNull);
      },
    );

    blocTest<ConnectionsCubit, ConnectionsState>(
      'updateConnection edits the matching entry in place',
      build: ConnectionsCubit.new,
      act: (cubit) => cubit.updateConnection('office-imac', name: 'Home iMac', address: '10.0.0.9'),
      expect: () => [const UpdateConnectionSuccessState()],
      verify: (cubit) {
        expect(cubit.connections, hasLength(2));
        final updated = cubit.byId('office-imac');
        expect(updated?.name, 'Home iMac');
        expect(updated?.address, '10.0.0.9');
      },
    );

    blocTest<ConnectionsCubit, ConnectionsState>(
      'removeConnection deletes the matching entry',
      build: ConnectionsCubit.new,
      act: (cubit) => cubit.removeConnection('office-imac'),
      expect: () => [const RemoveConnectionSuccessState()],
      verify: (cubit) {
        expect(cubit.connections, hasLength(1));
        expect(cubit.byId('office-imac'), isNull);
      },
    );
  });
}
