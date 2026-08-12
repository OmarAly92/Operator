import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class MuxSocket {
  Future<void> get ready;
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close();
}

class IOMuxSocket implements MuxSocket {
  IOMuxSocket(this._channel);

  factory IOMuxSocket.connect(Uri uri, Map<String, String> headers) =>
      IOMuxSocket(IOWebSocketChannel.connect(uri, headers: headers));

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
