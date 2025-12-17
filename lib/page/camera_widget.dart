import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lali_project/parametres/Camera.dart';
import 'package:lali_project/camera/client.dart';
import 'package:lali_project/camera/server.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:async';

// Enum pour le mode d'opération
enum OperationMode { client, server }

class CameraWidget extends StatefulWidget {
  const CameraWidget({super.key});

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Instance du vrai client
  final CameraClient _cameraClient = CameraClient();

  // Instance du vrai serveur
  final CameraServer _cameraServer = CameraServer(port: 8080);

  // Contrôleurs pour les champs de texte
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  // États pour le mode d'opération
  OperationMode _operationMode = OperationMode.client;

  // Liste des serveurs découverts
  final List<Map<String, dynamic>> _discoveredServers = [];
  bool _isScanning = false;
  double _scanProgress = 0.0;

  // Variables GPS
  bool _gpsEnabled = false;
  String _currentLocation = "Non disponible";
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _portController.text = '8080';
    _loadSettings();
    _loadOperationMode();
    _setupClientListeners();
    _setupServerListeners();
  }

  void _setupClientListeners() {
    // Écoute des changements de connexion
    _cameraClient.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {});
      }
    });

    // Écoute des mises à jour de statut
    _cameraClient.statusStream.listen((status) {
      if (mounted) {
        setState(() {});
      }
    });

    // Écoute des messages
    _cameraClient.messageStream.listen((message) {
      if (mounted) {
        _showToast(message);
      }
    });
  }

  void _setupServerListeners() {
    // Écoute des changements de statut du serveur
    _cameraServer.statusStream.listen((status) {
      if (mounted) {
        setState(() {});
      }
    });

    // Écoute des logs du serveur
    _cameraServer.logStream.listen((log) {
      if (mounted) {
        setState(() {});
      }
    });

    // Écoute des statistiques du serveur
    _cameraServer.statsStream.listen((stats) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadOperationMode() async {
    try {
      final mode = await CameraSettingsManager.getOperationMode();
      setState(() {
        _operationMode = mode;
      });
    } catch (e) {
      debugPrint('Erreur chargement mode opération: $e');
    }
  }

  Future<void> _saveOperationMode(OperationMode mode) async {
    try {
      await CameraSettingsManager.setOperationMode(mode);
      setState(() {
        _operationMode = mode;
      });
      
      // Arrêter le serveur si on passe en mode client
      if (mode == OperationMode.client && _cameraServer.isRunning) {
        await _cameraServer.stopServer();
      }
      
      _showToast('Mode ${mode == OperationMode.client ? 'client' : 'serveur'} activé');
    } catch (e) {
      debugPrint('Erreur sauvegarde mode: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final serverIP = await CameraSettingsManager.getServerIP();
      final serverPort = await CameraSettingsManager.getServerPort();
      
      _ipController.text = serverIP;
      _portController.text = serverPort.toString();
      
      bool autoConnect = await CameraSettingsManager.getAutoConnect();
      if (autoConnect && _operationMode == OperationMode.client && serverIP.isNotEmpty) {
        _connectToServer();
      }
    } catch (e) {
      debugPrint('Erreur chargement paramètres: $e');
    }
  }

  // === DIALOGUES DE CONFIGURATION ===

  void _showOperationModeDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'CONFIGURATION DU MODE',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 20),
              
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choisissez le mode d\'opération de l\'application:',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 30),
                      
                      // Option Client
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _operationMode == OperationMode.client 
                                ? Colors.blue 
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.computer,
                            color: _operationMode == OperationMode.client 
                                ? Colors.blue 
                                : Colors.grey,
                          ),
                          title: const Text(
                            'Mode Client',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Connectez-vous à un serveur de caméra distant'),
                          trailing: _operationMode == OperationMode.client
                              ? const Icon(Icons.check_circle, color: Colors.blue)
                              : null,
                          onTap: () {
                            _saveOperationMode(OperationMode.client);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Option Serveur
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _operationMode == OperationMode.server 
                                ? Colors.green 
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.dns,
                            color: _operationMode == OperationMode.server 
                                ? Colors.green 
                                : Colors.grey,
                          ),
                          title: const Text(
                            'Mode Serveur',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Hébergez un serveur de caméra pour les clients'),
                          trailing: _operationMode == OperationMode.server
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                          onTap: () {
                            _saveOperationMode(OperationMode.server);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      
                      // Informations serveur si mode serveur sélectionné
                      if (_operationMode == OperationMode.server) ...[
                        const SizedBox(height: 20),
                        Card(
                          elevation: 2,
                          color: Colors.green[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'INFORMATIONS SERVEUR',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FutureBuilder<String?>(
                                  future: _getServerAddress(),
                                  builder: (context, snapshot) {
                                    final serverInfo = snapshot.data ?? 'Chargement...';
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Adresse: $serverInfo',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Port: ${_cameraServer.port}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Statut: ${_cameraServer.isRunning ? "En cours" : "Arrêté"}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _cameraServer.isRunning ? Colors.green : Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 20),
                      
                      // Information importante
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Information importante:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Pour une vraie connexion entre appareils, vous avez besoin:',
                              style: TextStyle(fontSize: 12),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '• Les appareils doivent être sur le même réseau Wi-Fi',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '• Une application serveur doit être active sur l\'autre appareil',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '• Les ports doivent être ouverts dans le firewall',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Boutons d'action
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ANNULER'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAdvancedSettings();
                      },
                      child: const Text('PARAMÈTRES AVANCÉS'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> _getServerAddress() async {
  try {
    final networkInfo = NetworkInfo();
    final String? wifiIP = await networkInfo.getWifiIP();
    return wifiIP;
  } catch (e) {
    return 'Adresse non disponible';
  }
}
  void _showClientConfigDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.75,
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'CONFIGURATION CLIENT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Configuration IP et Port
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Paramètres de connexion',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _ipController,
                                decoration: const InputDecoration(
                                  labelText: 'Adresse IP du serveur',
                                  hintText: '10.67.239.152',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.computer),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.numbers),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _connectToServer,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[800],
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.link),
                                label: const Text('CONNECTER'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showNetworkScanDialog,
                                icon: const Icon(Icons.search),
                                label: const Text('SCANNER RÉSEAU'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Statut de connexion
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _cameraClient.isConnected ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _cameraClient.isConnected ? 'CONNECTÉ AU SERVEUR' : 'DÉCONNECTÉ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _cameraClient.isConnected ? Colors.green : Colors.red,
                                ),
                              ),
                              Text(
                                _cameraClient.connectionStatus,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        if (_cameraClient.isConnected)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: _disconnectFromServer,
                            tooltip: 'Déconnecter',
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Contrôles serveur si connecté
                if (_cameraClient.isConnected)
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'CONTRÔLES SERVEUR',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _capturePhotoRemote,
                                icon: const Icon(Icons.photo_camera, size: 16),
                                label: const Text('Prendre Photo'),
                              ),
                              ElevatedButton.icon(
                                onPressed: _toggleRemoteRecording,
                                icon: Icon(
                                  _cameraClient.isRecording ? Icons.stop : Icons.videocam,
                                  size: 16,
                                ),
                                label: Text(_cameraClient.isRecording ? 'Arrêter Vidéo' : 'Démarrer Vidéo'),
                              ),
                              ElevatedButton.icon(
                                onPressed: _toggleRemoteStreaming,
                                icon: Icon(
                                  _cameraClient.isStreaming ? Icons.cast_connected : Icons.cast,
                                  size: 16,
                                ),
                                label: Text(_cameraClient.isStreaming ? 'Arrêter Stream' : 'Démarrer Stream'),
                              ),
                              ElevatedButton.icon(
                                onPressed: _switchRemoteCamera,
                                icon: const Icon(Icons.cameraswitch, size: 16),
                                label: const Text('Changer Caméra'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                
                const Spacer(),
                
                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('FERMER'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAdvancedSettings();
                        },
                        child: const Text('PARAMÈTRES'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNetworkScanDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.75,
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'SCAN DU RÉSEAU',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Bouton de scan
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.search, size: 48, color: Colors.blue),
                        const SizedBox(height: 16),
                        const Text(
                          'Recherche des serveurs de caméra sur le réseau local',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        
                        if (_isScanning) ...[
                          Column(
                            children: [
                              CircularProgressIndicator(
                                value: _scanProgress,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Scan en cours... ${(_scanProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: _scanNetworkForCameras,
                            icon: const Icon(Icons.search),
                            label: const Text('LANCER LE SCAN'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Liste des serveurs découverts
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'SERVEURS DÉCOUVERTS',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _discoveredServers.isEmpty && !_isScanning
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text(
                                          'Aucun serveur trouvé',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                        Text(
                                          'Lancez le scan pour découvrir les caméras',
                                          style: TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _discoveredServers.length,
                                    itemBuilder: (context, index) {
                                      final server = _discoveredServers[index];
                                      return ListTile(
                                        leading: Icon(
                                          Icons.videocam, 
                                          color: server['status'] == 'En ligne' ? Colors.green : Colors.grey
                                        ),
                                        title: Text('${server['ip']}:${server['port']}'),
                                        subtitle: Text('Serveur de caméra - ${server['status']}'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.link, color: Colors.blue),
                                          onPressed: () {
                                            _connectToDiscoveredServer(server['ip'], server['port']);
                                            Navigator.pop(context);
                                          },
                                        ),
                                        onTap: () {
                                          _connectToDiscoveredServer(server['ip'], server['port']);
                                          Navigator.pop(context);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('FERMER'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showServerConfigDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.75,
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'CONFIGURATION SERVEUR',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Contrôle du serveur
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _cameraServer.isRunning ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _cameraServer.currentStatus,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _cameraServer.isRunning ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _toggleServer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _cameraServer.isRunning ? Colors.red : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_cameraServer.isRunning ? 'ARRÊTER' : 'DÉMARRER'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Statistiques du serveur
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _buildServerStatItem('Clients', _cameraServer.connectedClients.length.toString()),
                            _buildServerStatItem('Photos', _cameraServer.photosCaptured.toString()),
                            _buildServerStatItem('Vidéos', _cameraServer.videosRecorded.toString()),
                            _buildServerStatItem('Connexions', _cameraServer.totalConnections.toString()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Logs du serveur
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'LOGS DU SERVEUR',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _cameraServer.isRunning
                                ? ListView.builder(
                                    reverse: true,
                                    itemCount: _cameraServer.logMessages.length,
                                    itemBuilder: (context, index) {
                                      final log = _cameraServer.logMessages[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Text(
                                          log,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    },
                                  )
                                : const Center(
                                    child: Text(
                                      'Serveur arrêté',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('FERMER'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAdvancedSettings();
                        },
                        child: const Text('PARAMÈTRES'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildServerStatItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.green[600],
            ),
          ),
        ],
      ),
    );
  }

  void _showAdvancedSettings() {
    showDialog(
      context: context,
      builder: (context) => const CameraSettings(),
    );
  }

  // === MÉTHODES DE CONNEXION RÉSEAU ===

  Future<void> _connectToServer() async {
  final ip = _ipController.text.trim();
  final port = int.tryParse(_portController.text.trim()) ?? 8080;

  if (ip.isEmpty) {
    _showToast('Adresse IP requise');
    return;
  }

  setState(() {
    _cameraClient.setServer(ip, port);
  });

  try {
    final result = await _cameraClient.connectToServerWithRetry();
    
    if (result['success']) {
      await CameraSettingsManager.setServerIP(ip);
      await CameraSettingsManager.setServerPort(port);
      _showToast('✅ ${result['message']}');
    } else {
      // Afficher les détails de l'erreur
      _showConnectionErrorDialog(result);
    }
    
    setState(() {});
  } catch (e) {
    _showConnectionErrorDialog({
      'success': false,
      'error': 'Erreur inattendue',
      'details': e.toString()
    });
  }
}

void _showConnectionErrorDialog(Map<String, dynamic> errorResult) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('❌ Erreur de Connexion'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Erreur: ${errorResult['error']}'),
            const SizedBox(height: 12),
            if (errorResult['details'] != null) ...[
              const Text('Détails:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(errorResult['details']!, style: const TextStyle(fontSize: 12)),
            ],
            if (errorResult['type'] != null) ...[
              const SizedBox(height: 8),
              Text('Type: ${errorResult['type']}', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final errorText = '''
Erreur: ${errorResult['error']}
Détails: ${errorResult['details']}
Type: ${errorResult['type']}
IP: ${_ipController.text}
Port: ${_portController.text}
            ''';
            Clipboard.setData(ClipboardData(text: errorText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur copiée pour diagnostic')),
            );
          },
          child: const Text('COPIER POUR DIAGNOSTIC'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('FERMER'),
        ),
      ],
    ),
  );
}

  Future<void> _connectToDiscoveredServer(String ip, int port) async {
    _ipController.text = ip;
    _portController.text = port.toString();
    await _connectToServer();
  }

  // Nouvelle méthode de scan améliorée
Future<void> _scanNetworkForCameras() async {
  setState(() {
    _isScanning = true;
    _scanProgress = 0.0;
    _discoveredServers.clear();
  });

  String? errorMessage;
  List<String> scanLogs = [];

  try {
    final networkInfo = NetworkInfo();
    final String? wifiIP = await networkInfo.getWifiIP();
    
    scanLogs.add('📡 Début du scan réseau...');
    scanLogs.add('IP WiFi locale: ${wifiIP ?? 'Non disponible'}');

    if (wifiIP == null) {
      errorMessage = 'Impossible de détecter l\'adresse IP WiFi';
      scanLogs.add('❌ $errorMessage');
      _showScanResultsDialog(errorMessage, scanLogs);
      return;
    }

    // Analyser le sous-réseau
    final ipParts = wifiIP.split('.');
    if (ipParts.length != 4) {
      errorMessage = 'Format d\'adresse IP non supporté: $wifiIP';
      scanLogs.add('❌ $errorMessage');
      _showScanResultsDialog(errorMessage, scanLogs);
      return;
    }

    final networkPrefix = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
    scanLogs.add('Sous-réseau détecté: $networkPrefix.xxx');
    
    // Plages d'IP courantes pour les hotspots
    final List<String> networkRanges = [
      '$networkPrefix.1-254',  // Sous-réseau principal
      '10.67.1-254',           // Plage Orange fréquente
      '10.205.1-254',          // Plage SFR fréquente  
      '10.105.1-254',          // Plage Free fréquente
      '192.168.1.1-254',       // Routeurs classiques
      '192.168.0.1-254',       // Routeurs classiques
    ];

    // Supprimer les doublons et garder les plages uniques
    final uniqueRanges = networkRanges.toSet().toList();
    int totalIPs = 0;
    final List<String> allIPs = [];

    // Générer toutes les IPs à scanner
    for (final range in uniqueRanges) {
      final ips = await _generateIPsFromRange(range);
      allIPs.addAll(ips);
      totalIPs += ips.length;
      scanLogs.add('🔍 Plage $range: ${ips.length} IPs à scanner');
    }

    scanLogs.add('📊 Total des IPs à scanner: $totalIPs');

    if (totalIPs == 0) {
      errorMessage = 'Aucune IP à scanner dans les plages réseau';
      scanLogs.add('❌ $errorMessage');
      _showScanResultsDialog(errorMessage, scanLogs);
      return;
    }

    int completed = 0;
    final List<Future<void>> scanFutures = [];

    // Scanner avec gestion de progression
    for (final ip in allIPs) {
      final future = _scanIPAddress(ip).then((_) {
        completed++;
        setState(() {
          _scanProgress = completed / totalIPs;
        });
      });
      scanFutures.add(future);
    }

    // Exécuter par lots de 5 avec délai
  for (int i = 0; i < scanFutures.length; i += 5) {
    final endIndex = i + 5 < scanFutures.length ? i + 5 : scanFutures.length;
    final batch = scanFutures.sublist(i, endIndex);
    await Future.wait(batch);
    await Future.delayed(const Duration(milliseconds: 200)); // Éviter le flooding
  
    scanLogs.add('✅ Lot ${(i ~/ 5) + 1} terminé - ${_discoveredServers.length} serveur(s) trouvé(s)');
  }

    // Scanner aussi l'IP manuelle spécifiée
    final manualIP = _ipController.text.trim();
    if (manualIP.isNotEmpty && !allIPs.contains(manualIP)) {
      scanLogs.add('🔍 Scan de l\'IP manuelle: $manualIP');
      await _scanIPAddress(manualIP);
    }

    // Résultats finaux
    if (_discoveredServers.isEmpty) {
      scanLogs.add('❌ Aucun serveur de caméra trouvé');
      _showScanResultsDialog('Aucun serveur trouvé', scanLogs);
    } else {
      scanLogs.add('🎉 Scan terminé: ${_discoveredServers.length} serveur(s) trouvé(s)');
      _showScanResultsDialog(null, scanLogs);
    }

  } catch (e) {
    errorMessage = 'Erreur lors du scan: ${e.toString()}';
    scanLogs.add('❌ $errorMessage');
    _showScanResultsDialog(errorMessage, scanLogs);
  } finally {
    setState(() {
      _isScanning = false;
    });
  }
}

void _showScanResultsDialog(String? error, List<String> logs) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                error != null ? '❌ SCAN ÉCHOUÉ' : '✅ RÉSULTATS DU SCAN',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: error != null ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              
              // Résumé
              Card(
                color: error != null ? Colors.red[50] : Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        error != null ? Icons.warning : Icons.check_circle,
                        color: error != null ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error != null ? 'Scan échoué' : 'Scan terminé avec succès',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: error != null ? Colors.red : Colors.green,
                              ),
                            ),
                            Text(
                              error ?? '${_discoveredServers.length} serveur(s) trouvé(s)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Logs détaillés
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text(
                          'LOGS DE SCAN DÉTAILLÉS',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              final isError = log.contains('❌');
                              final isSuccess = log.contains('✅');
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isError ? Colors.red : 
                                           isSuccess ? Colors.green : Colors.grey[700],
                                    fontWeight: isError || isSuccess ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Boutons d'action
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final logText = logs.join('\n');
                        Clipboard.setData(ClipboardData(text: logText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logs copiés dans le presse-papier')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('COPIER LES LOGS'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: error != null ? Colors.red : Colors.green,
                      ),
                      child: const Text('FERMER', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Génération des IPs depuis une plage
Future<List<String>> _generateIPsFromRange(String range) async {
  final List<String> ips = [];
  
  try {
    if (range.contains('-')) {
      final parts = range.split('.');
      final ipBase = '${parts[0]}.${parts[1]}.${parts[2]}';
      final rangeParts = parts[3].split('-');
      
      final start = int.parse(rangeParts[0]);
      final end = int.parse(rangeParts[1]);
      
      for (int i = start; i <= end; i++) {
        ips.add('$ipBase.$i');
      }
    } else {
      // IP unique
      ips.add(range);
    }
  } catch (e) {
    debugPrint('Erreur génération IPs pour $range: $e');
  }
  
  return ips;
}

// Méthode de scan d'IP améliorée
Future<void> _scanIPAddress(String ip) async {
  final customPort = int.tryParse(_portController.text.trim()) ?? 8080;
  final commonPorts = [customPort, 8080, 8081, 8082, 8000, 8888, 5000, 3000];
  
  for (final port in commonPorts) {
    try {
      final uri = Uri.parse('http://$ip:$port/status');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          final serverName = data['device_name'] ?? 
                            data['camera_name'] ?? 
                            data['server_name'] ??
                            data['status'] ?? 
                            'Serveur Caméra';
          
          // Vérifier si c'est bien un serveur de caméra
          final bool isCameraServer = 
              serverName.toString().toLowerCase().contains('camera') ||
              serverName.toString().toLowerCase().contains('serveur') ||
              (data['camera_ready'] != null) ||
              (data['streaming'] != null) ||
              (data['recording'] != null);

          if (isCameraServer && !_discoveredServers.any((server) => server['ip'] == ip && server['port'] == port)) {
            setState(() {
              _discoveredServers.add({
                'ip': ip,
                'port': port,
                'status': 'En ligne',
                'name': serverName.toString(),
                'details': data
              });
            });
            break; // Arrêter après avoir trouvé un port valide
          }
        } catch (e) {
          // Même si le JSON est invalide, considérer comme serveur valide si réponse 200
          if (!_discoveredServers.any((server) => server['ip'] == ip && server['port'] == port)) {
            setState(() {
              _discoveredServers.add({
                'ip': ip,
                'port': port,
                'status': 'En ligne',
                'name': 'Serveur HTTP',
                'details': {'raw_response': response.body}
              });
            });
            break;
          }
        }
      }
    } catch (e) {
      // Continuer avec le port suivant
      continue;
    }
  }
}

 void _showLocationDialog(String googleMapsUrl) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue),
            SizedBox(width: 8),
            Text('Position Partagée'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Votre position a été partagée avec succès.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ouvrir dans Google Maps:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            if (googleMapsUrl.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _launchGoogleMaps(googleMapsUrl);
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.map, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ouvrir Google Maps',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _currentLocation,
                              style: TextStyle(
                                color: Colors.blue[600],
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.open_in_new, color: Colors.blue[700], size: 16),
                    ],
                  ),
                ),
              )
            else
              Text(
                _currentLocation,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FERMER'),
          ),
          if (googleMapsUrl.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                _launchGoogleMaps(googleMapsUrl);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('OUVRIR MAPS'),
            ),
        ],
      );
    },
  );
}

  Future<void> _launchGoogleMaps(String url) async {
  try {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      _showToast('Impossible d\'ouvrir Google Maps');
    }
  } catch (e) {
    _showToast('Erreur: $e');
  }
}

  // === MÉTHODES DE CONTRÔLE CAMÉRA ===

  Future<void> _capturePhotoRemote() async {
    try {
      final result = await _cameraClient.capturePhoto();
      if (result['success']) {
        _showToast('Photo capturée: ${result['file_path']}');
      } else {
        _showToast('Erreur capture: ${result['error']}');
      }
    } catch (e) {
      _showToast('Erreur capture: $e');
    }
  }

  Future<void> _toggleRemoteRecording() async {
    try {
      final result = await _cameraClient.toggleRecording();
      if (result['success']) {
        if (_cameraClient.isRecording) {
          _showToast('Enregistrement démarré');
        } else {
          _showToast('Enregistrement arrêté: ${result['file_path']}');
        }
      } else {
        _showToast('Erreur enregistrement: ${result['error']}');
      }
      setState(() {});
    } catch (e) {
      _showToast('Erreur enregistrement: $e');
    }
  }

  Future<void> _switchRemoteCamera() async {
    try {
      final result = await _cameraClient.switchCamera();
      if (result['success']) {
        _showToast('Caméra changée: ${result['camera']}');
      } else {
        _showToast('Erreur changement caméra: ${result['error']}');
      }
    } catch (e) {
      _showToast('Erreur changement caméra: $e');
    }
  }

  Future<void> _toggleFlash() async {
    try {
      final result = await _cameraClient.toggleFlash();
      if (result['success']) {
        _showToast('Flash ${result['flash_mode'] == 'on' ? 'activé' : 'désactivé'}');
      } else {
        _showToast('Erreur flash: ${result['error']}');
      }
    } catch (e) {
      _showToast('Erreur flash: $e');
    }
  }

  Future<void> _setTimer() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int selectedSeconds = 5;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Minuterie Photo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Délai avant capture:'),
                  const SizedBox(height: 16),
                  DropdownButton<int>(
                    value: selectedSeconds,
                    items: [3, 5, 10, 15, 30].map((seconds) {
                      return DropdownMenuItem<int>(
                        value: seconds,
                        child: Text('$seconds secondes'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedSeconds = value!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ANNULER'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _startTimerCapture(selectedSeconds);
                  },
                  child: const Text('DÉMARRER'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startTimerCapture(int seconds) async {
    _showToast('Capture dans $seconds secondes...');
    
    try {
      final result = await _cameraClient.setTimer(seconds);
      if (result['success']) {
        for (int i = seconds; i > 0; i--) {
          await Future.delayed(const Duration(seconds: 1));
          if (i <= 3) {
            _showToast('$i...');
          }
        }
        await _capturePhotoRemote();
      } else {
        _showToast('Erreur minuterie: ${result['error']}');
      }
    } catch (e) {
      _showToast('Erreur minuterie: $e');
    }
  }

  Future<void> _disconnectFromServer() async {
    await _cameraClient.disconnectFromServer();
    setState(() {});
  }

  Future<void> _toggleServer() async {
    try {
      if (_cameraServer.isRunning) {
        await _cameraServer.stopServer();
        _showToast('Serveur arrêté');
      } else {
        await _cameraServer.initialize();
        _showToast('Serveur démarré sur le port ${_cameraServer.port}');
        
        // Obtenir et afficher l'IP du serveur
        final networkInfo = NetworkInfo();
        final String? wifiIP = await networkInfo.getWifiIP();
        if (wifiIP != null) {
          _showToast('Adresse serveur: $wifiIP:${_cameraServer.port}');
        }
      }
      setState(() {});
    } catch (e) {
      _showToast('Erreur serveur: $e');
    }
  }

  // === MÉTHODES GPS ===

  Future<void> _toggleGPS() async {
    try {
      if (_gpsEnabled) {
        final result = await _cameraClient.stopGPS();
        if (result['success']) {
          setState(() {
            _gpsEnabled = false;
            _currentLocation = "Non disponible";
          });
          _showToast('GPS désactivé');
        } else {
          _showToast('Erreur désactivation GPS: ${result['error']}');
        }
      } else {
        final result = await _cameraClient.startGPS();
        if (result['success']) {
          setState(() {
            _gpsEnabled = true;
            _currentLocation = result['location'] ?? "Localisation inconnue";
          });
          _showToast('GPS activé: $_currentLocation');
        } else {
          _showToast('Erreur activation GPS: ${result['error']}');
        }
      }
    } catch (e) {
      _showToast('Erreur GPS: $e');
    }
  }

  Future<void> _updateCurrentLocation() async {
    if (!_gpsEnabled) {
      _showToast('GPS non activé');
      return;
    }

    setState(() {
      _isGettingLocation = true;
    });

    try {
      final result = await _cameraClient.getCurrentLocation();
      if (result['success']) {
        setState(() {
          _currentLocation = result['location'] ?? "Localisation inconnue";
          _isGettingLocation = false;
        });
        _showToast('Localisation: $_currentLocation');
      } else {
        _showToast('Erreur localisation: ${result['error']}');
        setState(() {
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      _showToast('Erreur localisation: $e');
      setState(() {
        _isGettingLocation = false;
      });
    }
  }

  Future<void> _shareCurrentLocation() async {
  if (!_gpsEnabled || _currentLocation == "Non disponible") {
    _showToast('Activez d\'abord le GPS');
    return;
  }

  try {
    final result = await _cameraClient.shareLocation(_currentLocation);
    if (result['success']) {
      // Afficher un dialogue avec le lien cliquable
      _showLocationDialog(result['google_maps_url'] ?? '');
    } else {
      _showToast('Erreur partage: ${result['error']}');
    }
  } catch (e) {
    _showToast('Erreur partage: $e');
  }
}

  Widget _buildGPSControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? color : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: enabled ? color : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: enabled ? color : Colors.grey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGPSControls() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'CONTRÔLES GPS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            
            // Affichage localisation actuelle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: _gpsEnabled ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Localisation: $_currentLocation',
                          style: TextStyle(
                            fontSize: 12,
                            color: _gpsEnabled ? Colors.black : Colors.grey,
                          ),
                        ),
                        if (_isGettingLocation)
                          const Text(
                            'Acquisition en cours...',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16),
                    onPressed: _gpsEnabled ? _updateCurrentLocation : null,
                    tooltip: 'Actualiser la localisation',
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Boutons GPS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _buildGPSControlButton(
                    icon: _gpsEnabled ? Icons.location_off : Icons.location_on,
                    label: _gpsEnabled ? 'Désactiver GPS' : 'Activer GPS',
                    color: _gpsEnabled ? Colors.red : Colors.green,
                    onTap: _toggleGPS,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildGPSControlButton(
                    icon: Icons.share,
                    label: 'Partager Position',
                    color: Colors.blue,
                    onTap: _shareCurrentLocation,
                    enabled: _gpsEnabled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // === INTERFACE UTILISATEUR ===

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'SYSTÈME CAMÉRA INTELLIGENTE',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue[800],
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _operationMode == OperationMode.client ? _showNetworkScanDialog : null,
            tooltip: 'Scanner le réseau pour les caméras',
          ),
          IconButton(
            icon: const Icon(Icons.device_hub, color: Colors.white),
            onPressed: () {
              if (_operationMode == OperationMode.client) {
                _showClientConfigDialog();
              } else {
                _showServerConfigDialog();
              }
            },
            tooltip: _operationMode == OperationMode.client 
                ? 'Configuration Client' 
                : 'Configuration Serveur',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showOperationModeDialog,
            tooltip: 'Paramètres du mode',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.blue[700],
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.camera_alt), text: 'CAMÉRA'),
                Tab(icon: Icon(Icons.settings), text: 'PARAMÈTRES'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCameraTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  Widget _buildCameraTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Affichage caméra
          _buildCameraDisplay(),
          
          // Indicateur de mode et statut
          _buildStatusIndicator(),
          
          // Section contrôle caméra
          _buildCameraControls(),
          
          // Section GPS si activé
          if (_operationMode == OperationMode.client) _buildGPSControls(),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Configuration rapide
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'CONFIGURATION RAPIDE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Mode d'opération
                  ListTile(
                    leading: Icon(
                      _operationMode == OperationMode.client ? Icons.computer : Icons.dns,
                      color: _operationMode == OperationMode.client ? Colors.blue : Colors.green,
                    ),
                    title: Text(
                      _operationMode == OperationMode.client ? 'Mode Client' : 'Mode Serveur',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _operationMode == OperationMode.client 
                          ? 'Connecté à un serveur distant' 
                          : 'Hébergement local',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _showOperationModeDialog,
                  ),
                  
                  const Divider(),
                  
                  // Configuration réseau
                  ListTile(
                    leading: const Icon(Icons.wifi, color: Colors.blue),
                    title: const Text(
                      'Configuration Réseau',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _operationMode == OperationMode.client 
                          ? 'Paramètres client' 
                          : 'Paramètres serveur',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      if (_operationMode == OperationMode.client) {
                        _showClientConfigDialog();
                      } else {
                        _showServerConfigDialog();
                      }
                    },
                  ),
                  
                  const Divider(),
                  
                  // Paramètres avancés
                  ListTile(
                    leading: const Icon(Icons.settings, color: Colors.orange),
                    title: const Text(
                      'Paramètres Avancés',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('Configuration détaillée'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _showAdvancedSettings,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Statistiques
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'STATISTIQUES',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Photos', _operationMode == OperationMode.client 
                          ? 'N/A' 
                          : _cameraServer.photosCaptured.toString()),
                      _buildStatItem('Vidéos', _operationMode == OperationMode.client 
                          ? 'N/A' 
                          : _cameraServer.videosRecorded.toString()),
                      _buildStatItem('Connexions', _operationMode == OperationMode.client 
                          ? (_cameraClient.isConnected ? '1' : '0')
                          : _cameraServer.connectedClients.length.toString()),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Informations système
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INFORMATIONS SYSTÈME',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSystemInfoItem('Version', '1.0.0'),
                  _buildSystemInfoItem('Mode', _operationMode == OperationMode.client ? 'Client' : 'Serveur'),
                  _buildSystemInfoItem('Statut', _operationMode == OperationMode.client 
                      ? (_cameraClient.isConnected ? 'Connecté' : 'Déconnecté')
                      : (_cameraServer.isRunning ? 'En cours' : 'Arrêté')),
                  if (_operationMode == OperationMode.client && _cameraClient.isConnected)
                    _buildSystemInfoItem('Serveur', '${_cameraClient.serverIP}:${_cameraClient.serverPort}'),
                  _buildSystemInfoItem('Dernière MAJ', 'Aujourd\'hui'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === WIDGETS RÉUTILISABLES ===

  Widget _buildStatusIndicator() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _operationMode == OperationMode.client 
            ? (_cameraClient.isConnected ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1))
            : (_cameraServer.isRunning ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _operationMode == OperationMode.client 
              ? (_cameraClient.isConnected ? Colors.green : Colors.orange)
              : (_cameraServer.isRunning ? Colors.green : Colors.orange),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _operationMode == OperationMode.client 
                ? Icons.computer 
                : Icons.dns,
            color: _operationMode == OperationMode.client 
                ? (_cameraClient.isConnected ? Colors.green : Colors.orange)
                : (_cameraServer.isRunning ? Colors.green : Colors.orange),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _operationMode == OperationMode.client 
                ? (_cameraClient.isConnected ? 'Connecté en mode Client' : 'Déconnecté - Mode Client')
                : (_cameraServer.isRunning ? 'Serveur Actif' : 'Serveur Arrêté'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _operationMode == OperationMode.client 
                  ? (_cameraClient.isConnected ? Colors.green : Colors.orange)
                  : (_cameraServer.isRunning ? Colors.green : Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  // REMPLACER la méthode _buildCameraDisplay() dans camera_widget.dart

Widget _buildCameraDisplay() {
  final screenHeight = MediaQuery.of(context).size.height;
  final cameraHeight = screenHeight * 0.4;

  return Container(
    margin: const EdgeInsets.all(16),
    height: cameraHeight,
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // AFFICHAGE DU FLUX VIDÉO RÉEL
          _buildCameraPreview(),
          
          // Badge de statut en haut à gauche
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: _operationMode == OperationMode.client
                        ? (_cameraClient.isConnected ? Colors.green : Colors.red)
                        : (_cameraServer.isRunning ? Colors.green : Colors.red),
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _operationMode == OperationMode.client
                        ? (_cameraClient.isConnected ? 'EN DIRECT' : 'HORS LIGNE')
                        : (_cameraServer.isRunning ? 'SERVEUR ACTIF' : 'SERVEUR ARRÊTÉ'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Badge enregistrement en haut à droite
          if ((_operationMode == OperationMode.client && _cameraClient.isRecording) ||
              (_operationMode == OperationMode.server && _cameraServer.isRecording))
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Informations supplémentaires en bas
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _operationMode == OperationMode.client ? 'Mode Client' : 'Mode Serveur',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  if (_gpsEnabled)
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'GPS Actif',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  if (_operationMode == OperationMode.client && _cameraClient.isConnected)
                    Text(
                      '${_cameraClient.serverIP}:${_cameraClient.serverPort}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// NOUVELLE MÉTHODE : Affiche le flux vidéo réel
 Widget _buildCameraPreview() {
  // MODE SERVEUR : Affiche la caméra locale
  if (_operationMode == OperationMode.server) {
    if (_cameraServer.isRunning && 
        _cameraServer.cameraController != null && 
        _cameraServer.cameraController!.value.isInitialized) {
      return CameraPreview(_cameraServer.cameraController!);
    } else {
      return _buildPlaceholder(
        icon: Icons.videocam_off,
        message: _cameraServer.isRunning 
            ? 'Initialisation de la caméra...' 
            : 'Démarrez le serveur pour voir la caméra',
      );
    }
  }
  
  // MODE CLIENT : Affiche le flux du serveur distant
  else {
    if (_cameraClient.isConnected) {
      // Si streaming actif, afficher le flux vidéo
      if (_cameraClient.isStreaming) {
        return _buildRemoteCameraStream();
      } else {
        return _buildPlaceholder(
          icon: Icons.video_camera_back,
          message: 'Démarrez le streaming pour voir le flux vidéo',
          color: Colors.orange,
        );
      }
    } else {
      return _buildPlaceholder(
        icon: Icons.cloud_off,
        message: 'Connectez-vous à un serveur',
        color: Colors.red,
      );
    }
  }
}

// Widget placeholder quand pas de caméra
Widget _buildPlaceholder({
  required IconData icon,
  required String message,
  Color? color,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 80,
          color: color ?? Colors.grey[600],
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? Colors.grey[600],
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}

// MÉTHODE POUR AFFICHER LE FLUX DISTANT (Mode Client)
 // REMPLACER _buildRemoteCameraStream dans camera_widget.dart
Widget _buildRemoteCameraStream() {
  return StreamBuilder<Uint8List>(
    stream: _cameraClient.videoStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _buildPlaceholder(
          icon: Icons.error,
          message: 'Erreur flux: ${snapshot.error}',
          color: Colors.red,
        );
      }

      if (!snapshot.hasData) {
        return _buildPlaceholder(
          icon: Icons.downloading,
          message: 'Chargement du flux...',
          color: Colors.blue,
        );
      }

      // Afficher l'image JPEG
      return Image.memory(
        snapshot.data!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame == null) {
            return _buildPlaceholder(
              icon: Icons.downloading,
              message: 'Chargement frame...',
              color: Colors.blue,
            );
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(
            icon: Icons.broken_image,
            message: 'Erreur image',
            color: Colors.red,
          );
        },
      );
    },
  );
}

// MODIFIER _toggleRemoteStreaming pour gérer le flux
Future<void> _toggleRemoteStreaming() async {
  try {
    if (_cameraClient.isStreaming) {
      final result = await _cameraClient.stopStreaming();
      await _cameraClient.stopVideoStream();
      if (result['success']) {
        _showToast('Streaming arrêté');
      }
    } else {
      final result = await _cameraClient.startStreaming();
      if (result['success']) {
        _showToast('Streaming démarré');
        // Démarrer la réception du flux vidéo
        _cameraClient.startVideoStream();
      } else {
        _showToast('Erreur streaming: ${result['error']}');
      }
    }
    setState(() {});
  } catch (e) {
    _showToast('Erreur streaming: $e');
  }
}

  Widget _buildCameraControls() {
    if (_operationMode == OperationMode.client) {
      return _buildClientControls();
    } else {
      return _buildServerControls();
    }
  }

  Widget _buildClientControls() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'CONTRÔLES CAMÉRA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            
            // Première ligne - 3 boutons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCameraControlButton(
                  icon: _cameraClient.isRecording ? Icons.stop : Icons.videocam,
                  label: _cameraClient.isRecording ? 'Arrêter Vidéo' : 'Démarrer Vidéo',
                  color: _cameraClient.isRecording ? Colors.red : Colors.red[400]!,
                  onTap: _toggleRemoteRecording,
                  enabled: _cameraClient.isConnected,
                ),
                _buildCameraControlButton(
                  icon: Icons.photo_camera,
                  label: 'Capture Photo',
                  color: Colors.blue[600]!,
                  onTap: _capturePhotoRemote,
                  enabled: _cameraClient.isConnected,
                ),
                _buildCameraControlButton(
                  icon: _cameraClient.isStreaming ? Icons.cast_connected : Icons.cast,
                  label: _cameraClient.isStreaming ? 'Stop Stream' : 'Démarrer Stream',
                  color: Colors.green[600]!,
                  onTap: _toggleRemoteStreaming,
                  enabled: _cameraClient.isConnected,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Deuxième ligne - 3 boutons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCameraControlButton(
                  icon: Icons.cameraswitch,
                  label: 'Changer Caméra',
                  color: Colors.orange[600]!,
                  onTap: _switchRemoteCamera,
                  enabled: _cameraClient.isConnected,
                ),
                _buildCameraControlButton(
                  icon: Icons.flash_on,
                  label: 'Flash',
                  color: Colors.yellow[700]!,
                  onTap: _toggleFlash,
                  enabled: _cameraClient.isConnected,
                ),
                _buildCameraControlButton(
                  icon: Icons.timer,
                  label: 'Minuterie',
                  color: Colors.purple[600]!,
                  onTap: _setTimer,
                  enabled: _cameraClient.isConnected,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerControls() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'CONTRÔLES SERVEUR',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildCameraControlButton(
                  icon: _cameraServer.isRecording ? Icons.stop : Icons.videocam,
                  label: _cameraServer.isRecording ? 'Arrêter' : 'Enregistrer',
                  color: _cameraServer.isRecording ? Colors.red : Colors.red[400]!,
                  onTap: () {
                    // Implémentation pour démarrer/arrêter l'enregistrement serveur
                    _showToast('Fonctionnalité serveur à implémenter');
                  },
                  enabled: _cameraServer.isRunning,
                ),
                _buildCameraControlButton(
                  icon: Icons.cameraswitch,
                  label: 'Changer Cam',
                  color: Colors.orange[600]!,
                  onTap: () {
                    _cameraServer.switchCamera();
                  },
                  enabled: _cameraServer.isRunning,
                ),
                _buildCameraControlButton(
                  icon: Icons.settings,
                  label: 'Résolution',
                  color: Colors.purple[600]!,
                  onTap: () {
                    _showResolutionDialog();
                  },
                  enabled: _cameraServer.isRunning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled ? color : Colors.grey,
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: enabled ? color : Colors.grey,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: enabled ? color : Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showResolutionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Changer la résolution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Basse'),
                onTap: () {
                  _cameraServer.changeResolution(ResolutionPreset.low);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Moyenne'),
                onTap: () {
                  _cameraServer.changeResolution(ResolutionPreset.medium);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Haute'),
                onTap: () {
                  _cameraServer.changeResolution(ResolutionPreset.high);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Très haute'),
                onTap: () {
                  _cameraServer.changeResolution(ResolutionPreset.veryHigh);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue[800],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cameraClient.dispose();
    _cameraServer.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }
}