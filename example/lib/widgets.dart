import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue/flutter_blue.dart';

import 'ble_device_data.dart';
import 'ble_handling.dart';

/// Dongle search expansion tile with bluetooth search function and list view of
/// scanned results. It shows a small loading indicator during the scan process.

// * Search Expansion Tile class Widget
class SearchExpansionTile extends StatefulWidget {
  final Function(BuildContext) onSearchPressed;

  SearchExpansionTile({Key key, this.onSearchPressed}) : super(key: key);

  @override
  SearchExpansionTileState createState() => new SearchExpansionTileState();
}

// * Search Expansion Tile State
class SearchExpansionTileState extends State<SearchExpansionTile> {
  //final GlobalKey<AppExpansionTileState> expansionTile = new GlobalKey();

  bool _showResults = false; // show Results only after a fresh scan!
  bool _showConnecting = false; // Show connecting state

  final String searchForMatchingName = "powerIO-Dongle";

  @override
  Widget build(BuildContext context) {
    final bleDeviceData = Provider.of<BleDeviceProvider>(context);
    final bleHandling = Provider.of<BleHandling>(context);

    return Container(
      child: Column(
        children: <Widget>[
          ListTile(
            title: Text(
              (bleDeviceData.bleDeviceData.device == null)
                  ? "N/A"
                  : bleDeviceData.bleDeviceData.device.name,
              style: TextStyle(fontSize: 16),
              maxLines: 1,
            ),
            trailing: SizedBox(child: _buildStateButtons(context), width: 38),
            leading: SizedBox(
              width: 100,
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: Icon(Icons.insert_drive_file),
                    onPressed: () async {
                      await bleHandling.sendFile();
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.text_fields),
                    onPressed: () async {
                      // let's send 2 messages after 1 second delay
                      Future.delayed(Duration(milliseconds: 300), () {})
                          .whenComplete(() {
                        bleHandling
                            .sendCommand("\$S\$1\$C\$onNetworkInit\$E\$")
                            .whenComplete(() {
                          Future.delayed(Duration(milliseconds: 300), () {})
                              .whenComplete(() {
                            bleHandling.sendCommand(
                                "\$S\$1\$C\$onSerialSettings\$E\$");
                          });
                        });
                      });

                      // await bleHandling.sendCommand(null);
                    },
                  ),
                ],
              ),
            ),
          ),
          StreamBuilder<bool>(
              stream: FlutterBlue.instance.isScanning,
              initialData: false,
              builder: (c, snapshot) {
                if (snapshot.data) {
                  return LinearProgressIndicator();
                } else {
                  return Container();
                }
              }),
          _buildScanResult(context),
        ],
      ),
    );
  }

  // build the correct buttons, for the current State
  // 1.) If there is no device selected and connected yet, then show the scanning buttons, to perform a scan.
  // 2.) In case of a valid device, then show the disconnect / button, because the connection has to be already connected in this state.
  // 3.) Otherwise, show the progress indicator, which means, that there is a current connecting progress running.
  Widget _buildStateButtons(BuildContext context) {
    final bleDeviceData = Provider.of<BleDeviceProvider>(context);

    if (bleDeviceData.bleDeviceData.device != null) {
      // Condition 3
      return _buildConnectionButton(
          context, bleDeviceData.bleDeviceData.device);
    } else {
      if (_showConnecting) {
        // Condition 2
        return CircularProgressIndicator();
      } else {
        // Condition 1
        return _buildSearchButton(context);
      }
    }
  }

  // builds the search button, based on the Stream condition of the scanning state.
  Widget _buildSearchButton(BuildContext context) {
    return StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              mini: true,
              onPressed: () {
                FlutterBlue.instance.stopScan();
              },
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                mini: true,
                onPressed: () {
                  setState(() {
                    widget.onSearchPressed(context);
                    _showResults = true;
                  });
                  FlutterBlue.instance.startScan(timeout: Duration(seconds: 4));
                  // expand the expansion tile instantly, without waiting for finish
                  //expansionTile.currentState.expand();
                });
          }
        });
  }

  // * builds the connection button
  Widget _buildConnectionButton(BuildContext context, BluetoothDevice device) {
    final bleDeviceData = Provider.of<BleDeviceProvider>(context);
    final bleHandling = Provider.of<BleHandling>(context);
    return StreamBuilder<BluetoothDeviceState>(
      stream: device.state,
      initialData: BluetoothDeviceState.connecting,
      builder: (c, snapshot) {
        switch (snapshot.data) {
          case BluetoothDeviceState.connected:
            return FloatingActionButton(
              child: Icon(Icons.bluetooth_connected),
              onPressed: () {
                bleHandling.unregisterUARTServices().whenComplete(() {
                  device.disconnect().whenComplete(() {
                    bleDeviceData.unregisterNewBleDevice();
                  });
                });
              },
              mini: true,
            );
          case BluetoothDeviceState.disconnected:
            return FloatingActionButton(
              child: Icon(Icons.bluetooth_disabled),
              onPressed: () {
                setState(() {
                  _showConnecting = true;
                });
                FlutterBlue.instance.stopScan();
                device.connect().whenComplete(() {
                  bleDeviceData.registerNewBleDevice(bleDevice: device);
                  bleHandling.registerUARTServices(device);
                  _showConnecting = false;
                  setState(() {
                    _showResults = false;
                  });
                });
              },
              mini: true,
            );
          default:
            return Container();
        }
      },
    );
  }

  // build the scan result list
  Widget _buildScanResult(BuildContext context) {
    final bleDeviceData = Provider.of<BleDeviceProvider>(context);

    if (bleDeviceData.bleDeviceData.device != null) {
      return Container();
    } else {
      // Only show scan results, when the Results, should be show (valid! - lack of FlutterBlue)
      if (_showResults) {
        return StreamBuilder<List<ScanResult>>(
          stream: FlutterBlue.instance.scanResults,
          initialData: [],
          builder: (c, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: snapshot.data
                .map(
                  (r) => _buildResultElement(context, r),
                )
                .toList(),
          ),
        );
      } else {
        return Container();
      }
    }
  }

  // result list elements
  Widget _buildResultElement(BuildContext context, ScanResult r) {
    if (r.advertisementData.localName == searchForMatchingName) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.grey[100],
              width: 1,
            ),
          ),
        ),
        child: ListTile(
          title: Text(
            r.advertisementData.localName.toString(),
          ),
          trailing: SizedBox(
              child: _buildConnectionButton(context, r.device), width: 32),
          leading: GestureDetector(
            child: Icon(Icons.add),
            onTap: () {
              print("add Dongle dialog");
            },
          ),
        ),
      );
    } else {
      return Container();
    }
  }
}
