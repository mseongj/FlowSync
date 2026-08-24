import 'dart:isolate';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
// import 'package:cryptography/cryptography.dart';

/// Represents a command sent to the CryptoWorkerIsolate
class CryptoCommand {
  final String type; // 'encrypt' or 'decrypt'
  final Map<String, dynamic> payload;
  CryptoCommand(this.type, this.payload);
}

/// The isolated worker that handles heavy cryptography
void cryptoWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is CryptoCommand) {
      if (message.type == 'decrypt') {
        // MOCK DECRYPTION (In prod, use AES-GCM from cryptography_flutter)
        // Simulate heavy work
        // final result = await _aesGcm.decrypt(...);
        mainSendPort.send({'status': 'success', 'data': 'decrypted_mock_data'});
      }
    }
  });
}

@lazySingleton
class CryptoWorkerManager {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _receivePort = ReceivePort();
  
  // Holds active keys in memory.
  // Wiped aggressively when AppLifecycle is backgrounded.
  Uint8List? _inMemoryMasterKey;

  Future<void> initialize() async {
    _isolate = await Isolate.spawn(cryptoWorkerEntry, _receivePort.sendPort);
    _receivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
      } else {
        // Handle responses from Isolate
      }
    });
  }

  void setActiveMasterKey(Uint8List key) {
    _inMemoryMasterKey = Uint8List.fromList(key);
  }

  void wipeMemory() {
    if (_inMemoryMasterKey != null) {
      for (int i = 0; i < _inMemoryMasterKey!.length; i++) {
        _inMemoryMasterKey![i] = 0;
      }
      _inMemoryMasterKey = null;
    }
  }

  void dispose() {
    wipeMemory();
    _receivePort.close();
    _isolate?.kill();
  }
}
