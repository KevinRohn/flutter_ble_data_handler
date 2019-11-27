import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:rxdart/rxdart.dart';

import 'package:flutter_ble_data_handler/handler.dart';

class BleHandling {
  Stream<bool> get dataIsReady => _dataIsReady.stream;

  Stream<String> get allDataOnStream => _allDataOnStream;

  BehaviorSubject<String> _allDataOnStream = BehaviorSubject.seeded("");

  BehaviorSubject<bool> _dataIsReady = BehaviorSubject.seeded(false);

  final StreamController<List<int>> _onDataReceivedController =
      StreamController<List<int>>.broadcast();

  Stream<List<int>> get onDataReceived => _onDataReceivedController.stream;

  BluetoothCharacteristic get rxCharacteristic => _rxCharacteristic;

  /// Characteristics
  BluetoothCharacteristic _txCharacteristic;
  BluetoothCharacteristic _rxCharacteristic;

  /// UART services
  final String uartServiceUUID = '49535343-FE7D-4AE5-8FA9-9FAFD205E455';
  final Guid uartService = Guid('49535343-FE7D-4AE5-8FA9-9FAFD205E455');
  final String uartTXCharUUID = '49535343-8841-43F4-A8D4-ECBE34729BB3';
  final String uartRXCharUUID = '49535343-1E4D-4BD9-BA61-23C647249616';

  /// Discover available services and search for the UART TX and RX
  Future<void> registerUARTServices(BluetoothDevice device) async {
    device.discoverServices().then((services) {
      services.forEach((service) {
        if (service.uuid.toString().toLowerCase() ==
            uartServiceUUID.toLowerCase()) {
          service.characteristics.forEach((characteristic) {
            if (characteristic.uuid.toString().toLowerCase() ==
                uartTXCharUUID.toLowerCase()) {
              _txCharacteristic = characteristic;
            } else if (characteristic.uuid.toString().toLowerCase() ==
                uartRXCharUUID.toLowerCase()) {
              _rxCharacteristic = characteristic;
              _rxCharacteristic.setNotifyValue(true);
              _rxCharacteristic.value.listen(listenToDataStream,
                  onError: onDataStreamError, onDone: onDataStreamDone);
              _dataIsReady.add(true);
            }
          });
        }
      });
    });
  }

  /// unregister UART Services
  Future<void> unregisterUARTServices() async {
    _rxCharacteristic.setNotifyValue(false);
    _dataIsReady.add(false);
  }

  Future<void> sendFile() async {
    await DataSender.instance
        .sendFile(_txCharacteristic, null, // null will be path here
            sendingCallback: UpdateHandler.instance.sendingCallback,
            chunkCountCallback: UpdateHandler.instance.chunkCountCallback,
            totalCountCallback: UpdateHandler.instance.totalCountCallback);
  }

  Future<void> sendCommand() async {
    await DataSender.instance
        .sendCommand(_txCharacteristic, null, // null will be command here
            sendingCallback: UpdateHandler.instance.sendingCallback,
            chunkCountCallback: UpdateHandler.instance.chunkCountCallback,
            totalCountCallback: UpdateHandler.instance.totalCountCallback);
  }

  void onDataStreamError(error, StackTrace stackTrace) {
    print("ERROR");
    print(error);

    if (stackTrace != null) {
      print(stackTrace);
    }
  }

  void onDataStreamDone() {
    print("DONE CALLED");
  }

  DataReceiver dataReceiver = DataReceiver();

  // Callback function to parse data
  Future<void> listenToDataStream(List<int> data) async {
    // needs to be more than 4 to be a data message
    if (!dataReceiver.onDataEvent(data)) {
      // data all arrived, we can dump
      dataReceiver.dump();
      _allDataOnStream.add("Data dumped.");
    } else {
      // debug to screen
      _allDataOnStream.add("Loading data...");
    }

  }
}
