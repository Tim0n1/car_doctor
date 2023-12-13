// ignore_for_file: prefer_const_constructors, non_constant_identifier_names

import 'dart:convert';
import 'package:vin_decoder/vin_decoder.dart';
import 'package:flatur/inferencePage.dart';
import 'package:flatur/liveDataPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:obd2_plugin/obd2_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flatur/trainingPage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui';
import 'obd2.dart';

String currentVersion = 'v0.1';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo',
      theme: ThemeData(
        primaryColor: Colors.pink,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
      home: BluetoothScreen(),
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothDevice? _connectedDevice;
  bool _bluetoothPermissionGranted = false;
  bool _notificationsPermissionsGranted = false;
  bool _serviceRunning = true;
  bool _isDeviceCompatible = true;
  bool _isDeviceCompatibleButtonEnabled = true;
  Map<String, String?> carInformation = {"manufacturer": null, "model": null};
  String vinNumber = '';
  Obd2Plugin obd2 = Obd2Plugin();

  //Stream<void>? _stream;
  StreamController _eventController = StreamController.broadcast();

  late Timer _deviceRefreshTimer;
  static const int _refreshInterval = 3; // Refresh interval in seconds

  Timer? _timer;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  // this will be used as notification channel id
  static const notificationChannelId = 'my_foreground';
// this will be used for notification id, So you can update your custom notification with this id.
  static const notificationId = 888;

  bool isConnected = false; // New variable to track connection status

  @override
  void initState() {
    print(111111);
    super.initState();
    _initBluetooth();
    _startDeviceRefreshTimer();
    startParamsExtraction();
  }

  @override
  void dispose() {
    _deviceRefreshTimer.cancel();
    //_subscription?.cancel();
    super.dispose();
  }

  Future<void> startParamsExtraction() async {
    while (true) {
      await Future.delayed(Duration(milliseconds: 1000));
      //print(_serviceRunning);
      if (!_serviceRunning) {
        print("service not running");
        return;
      }

      DartPluginRegistrant.ensureInitialized();

      if (_connectedDevice != null) {
        String response = '';
        if (!await obd2.hasConnection) {
          obd2.getConnection(
              _connectedDevice!, (connection) => null, (message) => null);
        } else {
          final FlutterLocalNotificationsPlugin
              flutterLocalNotificationsPlugin =
              FlutterLocalNotificationsPlugin();

          if (await obd2.hasConnection) {
            print('obd has connection');
            if (!(await obd2.isListenToDataInitialed)) {
              obd2.setOnDataReceived((command, response, requestCode) {
                if (!_eventController.isClosed) {
                  _eventController.add(response);
                } else {
                  print("startirame");
                  _eventController = StreamController.broadcast();
                }
                List<dynamic> parsedJson = [];
                parsedJson = json.decode(response);
                vinNumber = parsedJson[parsedJson.length - 1]['response'];

                print("$command => $response");
              });
            }

            await Future.delayed(Duration(
                milliseconds:
                    await obd2.getParamsFromJSON(StringJson().params)));
            // List<dynamic> parsedJson = [];
            // parsedJson = json.decode(response);
            // print("vin number $vinNumber");

            flutterLocalNotificationsPlugin.show(
              notificationId,
              'S',
              '${DateTime.now()}',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  notificationChannelId,
                  'MY FOREGROUND SERVICE',
                  icon: 'ic_bg_service_small',
                  ongoing: false,
                ),
              ),
            );
          }
        }
      } else {
        print('no connected device');
      }
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    if (await Permission.bluetooth.request().isGranted &&
        await Permission.bluetoothAdvertise.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.bluetoothScan.request().isGranted &&
        await Permission.location.request().isGranted) {
      return true;
    } else {
      return false;
    }
  }

  Future<void> _checkBluetoothPermission() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool permissionGranted =
        prefs.getBool('bluetoothPermissionGranted') ?? false;

    if (!permissionGranted) {
      // If permission not granted previously, request it now
      bool newPermissionGranted = await checkAndRequestPermissions();
      if (newPermissionGranted) {
        setState(() {
          _bluetoothPermissionGranted = true;
        });
        // Save the permission status in SharedPreferences
        await prefs.setBool('bluetoothPermissionGranted', true);
      }
    } else {
      setState(() {
        _bluetoothPermissionGranted = true;
      });
    }
  }

  Future<void> _checkNotificationsPermission() async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool permissionGranted =
        prefs.getBool('notificationsPermissionGranted') ?? false;

    if (!permissionGranted) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      bool? newPermissionGranted = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      if (newPermissionGranted!) {
        setState(() {
          _notificationsPermissionsGranted = true;
        });
        await prefs.setBool('notificationsPermissionGranted', true);
      }
    } else {
      setState(() {
        _notificationsPermissionsGranted = true;
      });
    }
  }

  Future<void> _initBluetooth() async {
    await _checkBluetoothPermission();
    await _checkNotificationsPermission();

    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    await _updateConnectedDevice();
  }

  Future<void> _updateConnectedDevice() async {
    List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].isConnected) {
        setState(() {
          _connectedDevice = devices[i];
          isConnected = true; // Update connection status
        });
        return;
      }
    }
    setState(() {
      _connectedDevice = null;
      isConnected = false; // Update connection status
    });
  }

  void _startDeviceRefreshTimer() {
    _deviceRefreshTimer =
        Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
      if (_bluetoothPermissionGranted && _notificationsPermissionsGranted) {
        _updateConnectedDevice();
      } // Update connected device status
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Car Doctor $currentVersion'),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              alignment: Alignment.topCenter,
              padding: EdgeInsets.only(top: 20), // Adjust top padding as needed
              child: Image.asset(
                'lib/images/logotobart.png', // Replace with your logo asset path
                width: 150, // Adjust width as needed
                height: 150, // Adjust height as needed
              ),
            ),
          ),
          Positioned(
            bottom: 150,
            left: 0,
            right: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => TrainingPage()));
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: 20, horizontal: 50), // Adjust padding
                    textStyle: TextStyle(fontSize: 18), // Adjust text size
                    minimumSize: Size(200, 60), // Adjust minimum button size
                  ),
                  child: Text('Training mode'),
                ),
                SizedBox(height: 16), // Add spacing between buttons
                ElevatedButton(
                  onPressed: _connectedDevice != null
                      ? () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => BackgroundServiceScreen(
                                        connectedDevice: _connectedDevice,
                                      )));
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: 20, horizontal: 50), // Adjust padding
                    textStyle: TextStyle(fontSize: 18), // Adjust text size
                    minimumSize: Size(200, 60), // Adjust minimum button size
                  ),
                  child: Text('Inference mode'),
                ),
                SizedBox(height: 80), // Add spacing between buttons
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => TrainingPage()));
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: 20, horizontal: 50), // Adjust padding
                    textStyle: TextStyle(fontSize: 18), // Adjust text size
                    minimumSize: Size(200, 60), // Adjust minimum button size
                  ),
                  child: Text('Fault log'),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => LiveDataPage(
                                  controller: _eventController,
                                )));
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: 20, horizontal: 50), // Adjust padding
                    textStyle: TextStyle(fontSize: 18), // Adjust text size
                    minimumSize: Size(200, 60), // Adjust minimum button size
                  ),
                  child: Text('Live data'),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 15,
            left: 0,
            child: Container(
              padding: EdgeInsets.all(8),
              //color: Colors.white.withOpacity(0.7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _bluetoothState == BluetoothState.STATE_ON
                        ? 'Bluetooth ON'
                        : 'Bluetooth OFF',
                    style: TextStyle(
                      color: _bluetoothState == BluetoothState.STATE_ON
                          ? Colors.green
                          : Colors.black,
                    ),
                  ),
                  SizedBox(height: 8), // Add spacing between texts
                  Text(
                    isConnected ? 'Connected Device:' : '',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_connectedDevice?.name ?? 'Not connected'}',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 15.0, right: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    !_isDeviceCompatible
                        ? "Device is not compatible"
                        : carInformation['manufacturer'] == null
                            ? 'Check OBD\n compatibility'
                            : "${carInformation['manufacturer']}\n${carInformation['model']}",
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                      // Add any other text styles as needed
                    ),
                  ),
                ),
                SizedBox(
                    width: 8), // Add some space between the button and text
                FloatingActionButton(
                  onPressed:
                      _isDeviceCompatibleButtonEnabled ? checkObdButton : null,
                  backgroundColor: Colors.transparent,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'lib/images/obd_icon.png', // Replace with your icon asset path
                        // Adjust height as needed
                        // You can also use other properties available in Image.asset
                      ),
                      if (!_isDeviceCompatibleButtonEnabled)
                        CircularProgressIndicator(
                          strokeAlign: BorderSide.strokeAlignOutside,
                          strokeWidth: 3,
                          color: Colors.white,
                        ), // Show loading indicator when isLoading is true
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> checkObdButton() async {
    setState(() {
      _isDeviceCompatibleButtonEnabled = false;
    });
    if (vinNumber.length > 17) {
      if (await obd2.isListenToDataInitialed) {
        await Future.delayed(Duration(milliseconds: 1500));
        vinNumber = vinNumber.substring(19);
        print(vinNumber);
        vinNumber = decodeHexASCII2(vinNumber);
        print(vinNumber.length);
        print(vinNumber);
        var vin = VIN(number: vinNumber, extended: true);
        print(vinNumber);
        String? model = await vin.getModelAsync();
        print(model);
        print(vin.getManufacturer());
        print(vinNumber);
        setState(() {
          _isDeviceCompatible = true;
          carInformation['manufacturer'] = vin.getManufacturer();
          carInformation['model'] = model;
        });
      }
    } else {
      setState(() {
        _isDeviceCompatible = false;
      });
    }
    setState(() {
      _isDeviceCompatibleButtonEnabled = true;
    });
  }

  // setState(() {
  //   _serviceRunning = false;
  //   print(_serviceRunning);
  // });
}
