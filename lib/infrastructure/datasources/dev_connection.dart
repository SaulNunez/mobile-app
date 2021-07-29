import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cobble/domain/connection/raw_incoming_packets_provider.dart';
import 'package:cobble/infrastructure/pigeons/pigeons.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final ConnectionControl connectionControl = ConnectionControl();

class DevConnection extends StateNotifier<DevConnState> {
  HttpServer? _server;
  WebSocket? _connectedSocket;
  StreamSubscription<Uint8List>? _incomingWatchPacketsSubscription;

  final Stream<Uint8List> _pebbleIncomingPacketStream;

  DevConnection(this._pebbleIncomingPacketStream)
      : super(DevConnState(false, false));

  void close() {
    disconnect();

    _server?.close();
    _server = null;

    _updateState();
  }

  void disconnect() {
    _connectedSocket?.close();
    _connectedSocket = null;

    _incomingWatchPacketsSubscription?.cancel();
    _incomingWatchPacketsSubscription = null;
  }

  void handleDevConnection(WebSocket socket, String ip) {
    if (_connectedSocket == null) {
      _connectedSocket = socket;
      _updateState();

      _incomingWatchPacketsSubscription =
          _pebbleIncomingPacketStream.listen(onPacketReceivedFromWatch);

      socket.listen(
        (event) {
          onPacketReceivedFromWebsocket(event as Uint8List);
        },
        onDone: () {
          disconnect();
          _updateState();
        },
        onError: (error) {
          disconnect();
          _updateState();
        },
        cancelOnError: true,
      );
    } else {
      socket.close(WebSocketStatus.internalServerError,
          "Only one developer connection is supported");
    }
  }

  void onPacketReceivedFromWebsocket(Uint8List indata) {
    if (indata[0] == 0x01) {
      Uint8List packet = indata.sublist(1);
      ListWrapper packetDataWrapper = ListWrapper();
      packetDataWrapper.value = packet.map((e) => e.toInt()).toList();
      connectionControl.sendRawPacket(packetDataWrapper);
      /*.then((res) {
        Uint8List rpacket = Uint8List(0x00) + (res as Uint8List);
        socket.add(rpacket);
      });*/
    }
  }

  void onPacketReceivedFromWatch(Uint8List data) {
    final connectedSocket = _connectedSocket;
    if (connectedSocket == null) {
      return;
    }

    final builder = BytesBuilder();
    builder.addByte(0x00);
    builder.add(data);

    var bytes = builder.toBytes();
    connectedSocket.add(bytes);
  }

  Future<void> start() async {
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      9000,
      shared: true,
    );

    _server = server;

    server.listen((event) {
      if (WebSocketTransformer.isUpgradeRequest(event)) {
        WebSocketTransformer.upgrade(event).then(
                (value) => handleDevConnection(value, server.address.address));
      }
    });

    _updateState();
  }

  void _updateState() {
    state = DevConnState(_server != null, _connectedSocket != null);
  }
}

class DevConnState {
  final bool running;
  final bool connected;

  DevConnState(this.running, this.connected);
}

final devConnectionProvider = StateNotifierProvider<DevConnection>((ref) {
  final incomingPacketsStream = ref.read(rawPacketStreamProvider);
  return DevConnection(incomingPacketsStream);
});
