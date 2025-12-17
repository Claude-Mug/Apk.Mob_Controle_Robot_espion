import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lali_project/page/vocal_widget.dart';
import 'package:lali_project/page/control_widget.dart';
import 'package:lali_project/page/camera_widget.dart';
import 'package:lali_project/modal_connexion/bluetooth.dart';
import 'package:lali_project/services/blue_manager.dart';
import 'package:lali_project/services/Services.Wifi.dart';
import 'package:lali_project/stockage/devices.dart';

class AccueilWidget extends StatefulWidget {
  const AccueilWidget({Key? key}) : super(key: key);

  @override
  State<AccueilWidget> createState() => _AccueilWidgetState();
}

class _AccueilWidgetState extends State<AccueilWidget> {
  // Instanciation des managers pour la connexion générale
  final BluetoothManager _bluetoothManager = BluetoothManager();
  final WiFiControlManager _wifiManager = WiFiControlManager();
  final DeviceHistoryManager _historyManager = DeviceHistoryManager();

  // Contrôleurs pour l'IP et le Port
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.150',
  );
  final TextEditingController _portController = TextEditingController(
    text: '80',
  );

  // État pour le protocole Wi-Fi et les messages
  bool _useWebSocket = false;
  String _wifiStatusMessage = '';
  bool _showConnectionPanel = false;
  String _connectionType = 'default';

  @override
  void initState() {
    super.initState();
    _bluetoothManager.connectionStateStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          if (isConnected) {
            _connectionType = 'bluetooth';
            _showConnectionPanel = false;
          } else if (_connectionType == 'bluetooth') {
            _connectionType = 'default';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _bluetoothManager.dispose();
    _wifiManager.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _toggleConnectionPanel(String type) {
    if (type != _connectionType) {
      _bluetoothManager.disconnectDevice();
    }

    setState(() {
      _connectionType = type;
      _showConnectionPanel = type == 'wifi';
      _wifiStatusMessage = '';
    });

    if (type == 'bluetooth') {
      _showBluetoothModal();
    }
  }

  void _resetConnection() {
    if (_connectionType == 'bluetooth') {
      _bluetoothManager.disconnectDevice();
    }

    setState(() {
      _connectionType = 'default';
      _showConnectionPanel = false;
    });
  }

  void _handleDeviceSelected(dynamic device) {
    _bluetoothManager.connectToDevice(device);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tentative de connexion à ${device.name}...')),
    );
  }
 

  void _showBluetoothModal() {
    BluetoothModal.show(
      context: context,
      manager: _bluetoothManager,
      onDeviceSelected: _handleDeviceSelected,
    );
  }

  // Méthode pour gérer la reconnexion depuis l'historique
  void _handleReconnectFromHistory(DeviceHistory device) {
  if (device.connectionType == 'bluetooth') {
    _bluetoothManager.connectToDevice(device.address);
    setState(() {
      _connectionType = 'bluetooth';
      _showConnectionPanel = false;
    });
  } else if (device.connectionType == 'wifi') {
    setState(() {
      _connectionType = 'wifi';
      _showConnectionPanel = true;
      _ipController.text = device.address;
      // Utiliser des valeurs par défaut pour le port
      _portController.text = '80';
      _useWebSocket = false; // Valeur par défaut
    });
    _connectWifi();
  }
}
 Future<void> _connectWifi() async {
  final ip = _ipController.text.trim();
  final port = int.tryParse(_portController.text.trim());

  print('=== DEBUG CONNEXION ===');
  print('IP: $ip, Port: $port');

  if (port == null) {
    setState(
      () => _wifiStatusMessage = 'Erreur : Le port doit être un nombre valide.',
    );
    return;
  }

  setState(() => _wifiStatusMessage = 'Connexion Wi-Fi en cours...');

  ConnectionResult result;
  final protocol = _useWebSocket ? WiFiProtocol.websocket : WiFiProtocol.http;
  _wifiManager.setActiveProtocol(protocol);

  if (_useWebSocket) {
    result = await _wifiManager.connectWebSocket(ip, port: port);
  } else {
    // UTILISEZ LA NOUVELLE MÉTHODE SANS COMMANDE
    result = await _wifiManager.connectHttp(ip, port: port);
  }

  setState(() {
    if (result.success) {
      _connectionType = 'wifi';
      _showConnectionPanel = false;
      _wifiStatusMessage = '✅ Connexion Wi-Fi $protocol OK !';
      
      _historyManager.addDevice(DeviceHistory(
        name: 'Appareil Wi-Fi $ip',
        address: ip,
        connectionType: 'wifi',
        lastConnected: DateTime.now(),
      ));
    } else {
      _wifiStatusMessage = '❌ Échec de connexion Wi-Fi: ${result.message}';
    }
  });

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_wifiStatusMessage)));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'La-Li_Control_Robot',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue[700],
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: _connectionType == 'wifi'
                    ? Icon(Icons.wifi, color: Colors.white)
                    : _connectionType == 'bluetooth'
                    ? Icon(Icons.bluetooth, color: Colors.white)
                    : Icon(Icons.link, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Type de connexion',
                        style: TextStyle(color: Colors.blue[700]),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.wifi,
                              color: _connectionType == 'wifi'
                                  ? Colors.green
                                  : Colors.blue[600],
                            ),
                            title: Text('Wifi'),
                            trailing: _connectionType == 'wifi'
                                ? Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              _toggleConnectionPanel('wifi');
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.bluetooth,
                              color: _connectionType == 'bluetooth'
                                  ? Colors.green
                                  : Colors.blue[600],
                            ),
                            title: Text('Bluetooth'),
                            trailing: _connectionType == 'bluetooth'
                                ? Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              _toggleConnectionPanel('bluetooth');
                            },
                          ),
                          Divider(),
                          ListTile(
                            leading: Icon(Icons.link_off, color: Colors.grey),
                            title: Text('Déconnecter'),
                            onTap: () {
                              Navigator.pop(context);
                              _resetConnection();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (_connectionType != 'default')
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: BoxConstraints(minWidth: 12, minHeight: 12),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.device_hub, color: Colors.white),
            onPressed: () {
              DeviceHistoryModal.show(
                context: context,
                manager: _historyManager,
                onReconnect: _handleReconnectFromHistory,
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // TODO: Naviguer vers la page des paramètres
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue[800]!, Colors.blue[400]!],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/image1.jpg',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              print("Erreur de chargement de l'image: $error");
                              return Container(
                                color: Colors.grey[300],
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.android,
                                      size: 80,
                                      color: Colors.blue[700],
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Image non trouvée\nVérifiez assets/image1.jpg',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        if (_connectionType != 'default')
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _connectionType == 'wifi'
                                        ? Icons.wifi
                                        : Icons.bluetooth,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    _connectionType == 'wifi' ? 'WiFi' : 'BT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildIconButton(
                              icon: Icons.camera_alt,
                              label: 'Camera',
                              color: Colors.red[400]!,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CameraWidget(),
                                  ),
                                );
                              },
                            ),
                            _buildIconButton(
                              icon: Icons.gamepad,
                              label: 'Control',
                              color: Colors.green[600]!,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ControlWidget(
                                      bluetoothManager: _bluetoothManager,
                                      wifiManager: _wifiManager,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 30),
                        _buildIconButton(
                          icon: Icons.mic,
                          label: 'Vocal',
                          color: Colors.orange[600]!,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VocalWidget(
                                  bluetoothManager: _bluetoothManager,
                                  wifiManager: _wifiManager,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_showConnectionPanel) _buildConnectionPanel(),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Text(
              'lali-robot-control',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            iconSize: 40,
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionPanel() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wifi, color: Colors.blue[700]),
                  SizedBox(width: 10),
                  Text(
                    'Connexion WiFi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey),
                    onPressed: _resetConnection,
                  ),
                ],
              ),
              SizedBox(height: 15),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: 'Adresse IP',
                  labelStyle: TextStyle(color: Colors.blue[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[700]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: Icon(Icons.computer, color: Colors.blue[600]),
                ),
              ),
              SizedBox(height: 15),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: 'Port',
                  labelStyle: TextStyle(color: Colors.blue[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[700]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: Icon(Icons.numbers, color: Colors.blue[600]),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Text('Utiliser WebSocket (Port 81)'),
                  Spacer(),
                  Switch(
                    value: _useWebSocket,
                    onChanged: (value) {
                      setState(() {
                        _useWebSocket = value;
                        if (value && _portController.text == '80') {
                          _portController.text = '81';
                        } else if (!value && _portController.text == '81') {
                          _portController.text = '80';
                        }
                      });
                    },
                    activeColor: Colors.blue[700],
                    inactiveTrackColor: Colors.grey[300],
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _wifiManager.hasActiveConnection
                            ? Colors.green[600]
                            : Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _resetConnection,
                      child: Text('Annuler'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _connectWifi,
                      child: Text(
                        'Connecter',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              if (_wifiStatusMessage.isNotEmpty)
                Text(
                  _wifiStatusMessage,
                  style: TextStyle(
                    color: _wifiStatusMessage.startsWith('✅')
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}