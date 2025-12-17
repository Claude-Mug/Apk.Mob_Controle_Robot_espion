// control_widget.dart
import 'dart:async';
import 'dart:convert'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lali_project/services/Services.Wifi.dart';
import 'package:lali_project/services/blue_manager.dart';
import 'package:lali_project/modal_connexion/bluetooth.dart';
import 'package:lali_project/modal_connexion/wifi.dart';
import 'package:lali_project/stockage/devices.dart';
import 'package:lali_project/parametres/control.dart';


 class ControlWidget extends StatefulWidget {
  final BluetoothManager bluetoothManager;
  final WiFiControlManager wifiManager;
  
  const ControlWidget({
    Key? key,
    required this.bluetoothManager,
    required this.wifiManager,
  }) : super(key: key);
  @override
  State<ControlWidget> createState() => _ControlWidgetState();
}

class _ControlWidgetState extends State<ControlWidget> {
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();
  // États des moteurs
  double _motor1Speed = 0.0;
  double _motor2Speed = 0.0;
  bool _isPaused = false;
  int _buzzerState = 0;
  double _ultrasonic1Distance = 0.0;
  bool _pirDetected = false;
  
  // État de connexion
  String _connectionType = 'wifi'; // 'wifi' ou 'bluetooth'
  String _connectedDeviceName = 'Aucun appareil';
  
  // Historique des commandes
  final List<CommandLog> _commandHistory = [];
  
  // Contrôleur pour la console
  final ScrollController _consoleController = ScrollController();

  // État pour afficher/masquer la console
  bool _showConsole = false;

  // AJOUT: Stream subscriptions pour écouter les réponses
  StreamSubscription? _webSocketMessagesSubscription;
  StreamSubscription? _webSocketStatusSubscription;
  StreamSubscription? _httpPollingMessagesSubscription;
  StreamSubscription? _wifiConnectivitySubscription;

  // Commandes personnalisées
  Map<String, String> _currentCommands = {};
  bool _motor1Inverted = false;
  bool _motor2Inverted = false;
  List<CustomControl> _customControls = [];

  @override
  void initState() {
    super.initState();
    _addToConsole('Système de contrôle initialisé', isSystem: true);
    _deviceHistoryManager.loadHistory();
    _loadCommands(); // AJOUTER CETTE LIGNE
   _loadCustomControls();
   _setupDeviceResponseListener();
  }

  void _loadCustomControls() async {
  final prefs = await SharedPreferences.getInstance();
  final customJson = prefs.getString('custom_controls');
  if (customJson != null) {
    try {
      final customList = List<dynamic>.from(json.decode(customJson));
      setState(() {
        _customControls = customList
            .map((item) => CustomControl.fromMap(Map<String, dynamic>.from(item)))
            .where((control) => control.isActive)
            .toList();
      });
    } catch (e) {
      print('Erreur chargement contrôles personnalisés: $e');
    }
  }
}

@override
void dispose() {
  // Nettoyer tous les listeners
  _webSocketMessagesSubscription?.cancel();
  _webSocketStatusSubscription?.cancel();
  _httpPollingMessagesSubscription?.cancel();
  _wifiConnectivitySubscription?.cancel();
  
  // Nettoyer le contrôleur de console
  _consoleController.dispose();
  
  super.dispose();
}

// AJOUTER CETTE MÉTHODE POUR ÉCOUTER LES RÉPONSES DU MICROCONTRÔLEUR
void _setupDeviceResponseListener() {
  // Écouter les messages WebSocket du microcontrôleur
  _webSocketMessagesSubscription = widget.wifiManager.webSocketMessages.listen((message) {
    _addToConsole('📟 ESP32: $message', isDeviceResponse: true);
  });

  // Écouter l'état de connexion WebSocket
  _webSocketStatusSubscription = widget.wifiManager.isWebSocketConnected.listen((isConnected) {
    if (isConnected) {
      _addToConsole('✅ Connexion WebSocket établie', isSystem: true);
    } else {
      _addToConsole('⚠️ Connexion WebSocket perdue', isSystem: true);
    }
  });

  // Écouter les réponses HTTP (polling)
  _httpPollingMessagesSubscription = widget.wifiManager.httpPollingMessages.listen((result) {
    if (result.success) {
      _addToConsole('📟 ESP32: ${result.message}', isDeviceResponse: true);
    } else {
      _addToConsole('❌ Erreur HTTP: ${result.message}', isError: true);
    }
  });

  // Écouter les changements de connectivité WiFi
  _wifiConnectivitySubscription = widget.wifiManager.wifiConnectivityStream.listen((status) {
    _addToConsole('📶 Statut réseau: $status', isSystem: true);
  });
}

  void _addToConsole(String message, {
  bool isSystem = false, 
  bool isError = false, 
  bool isDeviceResponse = false // NOUVEAU PARAMÈTRE
}) {
  setState(() {
    _commandHistory.insert(0, CommandLog(
      message: message,
      timestamp: DateTime.now(),
      isSystem: isSystem,
      isError: isError,
      isDeviceResponse: isDeviceResponse, // ASSIGNER LA VALEUR
    ));
    
    // Limiter l'historique à 100 messages
    if (_commandHistory.length > 100) {
      _commandHistory.removeLast();
    }
  });
  
  // Faire défiler vers le bas
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_consoleController.hasClients) {
      _consoleController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  });
}

  void _toggleConsole() {
    setState(() {
      _showConsole = !_showConsole;
    });
  }

  void _sendMotorCommand(String command, String value) {
  final baseCommand = _currentCommands['motor1'] ?? 'MOTOR:M1:PWM:';
  final fullCommand = baseCommand.replaceFirst('M1', command) + value;
  _sendCommand(fullCommand);
}

  void _updateMotor1Speed(double speed) {
    setState(() {
      _motor1Speed = speed;
    });
    _sendMotorCommand('M1', 'PWM:${(speed * 255).toInt()}');
  }

  void _updateMotor2Speed(double speed) {
    setState(() {
      _motor2Speed = speed;
    });
    _sendMotorCommand('M2', 'PWM:${(speed * 255).toInt()}');
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    _sendMotorCommand('ALL', _isPaused ? 'STOP' : 'START');
    _addToConsole(_isPaused ? '⏸️ Système mis en pause' : '▶️ Système activé', isSystem: true);
  }

  // control_widget.dart (inside _ControlWidgetState)

void _toggleBuzzerState() {
  String command;
  String logMessage;
  int newState;

  if (_buzzerState == 0) { // État actuel OFF (0) -> Passe à ON (1)
    command = _currentCommands['buzzer_on'] ?? 'BUZZER:ON';
    logMessage = 'Buzzer activé';
    newState = 1;
  } else if (_buzzerState == 1) { // État actuel ON (1) -> Passe à PAUSE (2)
    command = _currentCommands['buzzer_pause'] ?? 'BUZZER:PAUSE';
    logMessage = 'Buzzer mis en pause';
    newState = 2;
  } else { // État actuel PAUSE (2) -> Revient à OFF (0)
    command = _currentCommands['buzzer_off'] ?? 'BUZZER:OFF';
    logMessage = 'Buzzer arrêté';
    newState = 0;
  }

  setState(() {
    _buzzerState = newState;
  });
  _sendCommand(command);
  _addToConsole('🔊 $logMessage', isSystem: true);
}

  void _sendDirectionCommand(String direction) {
  String? commandText;
  switch (direction) {
    case 'Avant':
      commandText = _currentCommands['direction_forward'] ?? 'DIRECTION:Avant';    
      break;
    case 'Arriere':
      commandText = _currentCommands['direction_backward'] ?? 'DIRECTION:Arriere';
      break;
    case 'Gauche':
      commandText = _currentCommands['direction_left'] ?? 'DIRECTION:Gauche';
      break;
    case 'Droite':
      commandText = _currentCommands['direction_right'] ?? 'DIRECTION:Droite';
      break;
  }
  if (commandText != null) {
    _sendCommand(commandText);
  }
}

  void _clearConsole() {
    setState(() {
      _commandHistory.clear();
    });
    _addToConsole('Console effacée', isSystem: true);
  }

  // Dans control_widget.dart - _ControlWidgetState

// Méthode pour ouvrir la modal Bluetooth
// Méthode pour ouvrir la modal Bluetooth (AMÉLIORÉE)
 void _openBluetoothModal() async {
    _addToConsole('Ouverture du sélecteur Bluetooth...', isSystem: true);
    
    try {
      await BluetoothModal.show(
        context: context,
        manager: widget.bluetoothManager,
        onDeviceSelected: (device) {
          final deviceName = device.name ?? 'Appareil Bluetooth';
          _addToConsole('Appareil Bluetooth sélectionné: $deviceName', isSystem: true);
          
          // Ajouter à l'historique des appareils
          _deviceHistoryManager.addDevice(DeviceHistory(
            name: deviceName,
            address: device.address,
            connectionType: 'bluetooth',
            lastConnected: DateTime.now(),
          ));
          
          setState(() {
            _connectionType = 'bluetooth';
            _connectedDeviceName = deviceName;
          });
          _addToConsole('Mode de connexion changé: BLUETOOTH', isSystem: true);
        },
      );
    } catch (e) {
      _addToConsole('Erreur lors de l\'ouverture du modal Bluetooth: $e', isSystem: true, isError: true);
    }
  }

  // Remplacer la méthode _openWifiModal existante
  void _openWifiModal() async {
    _addToConsole('Ouverture du sélecteur WiFi...', isSystem: true);
    
    try {
      await WifiConnectionModal.show(
        context: context,
        manager: widget.wifiManager,
      );
      
      // Vérifier si la connexion WiFi a réussi
      if (widget.wifiManager.hasActiveConnection) {
        _addToConsole('Configuration WiFi terminée', isSystem: true);
        
        // Ajouter à l'historique des appareils
        _deviceHistoryManager.addDevice(DeviceHistory(
          name: 'Connexion WiFi',
          address: widget.wifiManager.connectionStatus,
          connectionType: 'wifi',
          lastConnected: DateTime.now(),
        ));
        
        setState(() {
          _connectionType = 'wifi';
          _connectedDeviceName = widget.wifiManager.connectionStatus;
        });
        _addToConsole('Mode de connexion changé: WIFI', isSystem: true);
      }
    } catch (e) {
      _addToConsole('Erreur lors de l\'ouverture du modal WiFi: $e', isSystem: true, isError: true);
    }
  }

  void _openDeviceHistory() {
    DeviceHistoryModal.show(
      context: context,
      manager: _deviceHistoryManager,
      onReconnect: (device) {
        _addToConsole('Tentative de reconnexion à ${device.name}', isSystem: true);
        
        if (device.connectionType == 'bluetooth') {
          _addToConsole('Reconnexion Bluetooth à ${device.name}', isSystem: true);
        } else if (device.connectionType == 'wifi') {
          _addToConsole('Reconnexion WiFi à ${device.name}', isSystem: true);
        }
        
        setState(() {
          _connectionType = device.connectionType;
          _connectedDeviceName = device.name;
        });
      },
    );
  }

 // CORRECTION: Vérification simplifiée
bool _isConnected() {
  if (_connectionType == 'wifi') {
    return widget.wifiManager.hasActiveConnection;
  } else if (_connectionType == 'bluetooth') {
    return widget.bluetoothManager.connectedDevice != null;
  }
  return false;
}

// Vérifier si prêt pour l'envoi (SIMPLIFIÉE)
bool _isReadyToSend() {
  if (!_isConnected()) {
    _addToConsole('❌ Aucune connexion active', isSystem: true, isError: true);
    return false;
  }
  return true;
} 
 
// Ajoutez cette méthode pour ouvrir les paramètres
 void _openSettingsDialog() {
  ControlSettingsDialog.show(
    context: context,
    bluetoothManager: widget.bluetoothManager,
    wifiManager: widget.wifiManager,
    onCommandsUpdated: (Map<String, String> commands) {
      setState(() {
        _currentCommands = commands;
      });
      _addToConsole('Commandes mises à jour', isSystem: true);
      
      // Recharger immédiatement les commandes dans les contrôleurs
      _reloadCommands();
    },
    onPWMInversionUpdated: (bool motor1Inverted, bool motor2Inverted) {
      setState(() {
        _motor1Inverted = motor1Inverted;
        _motor2Inverted = motor2Inverted;
      });
      _addToConsole('Inversion PWM mise à jour: M1=$motor1Inverted, M2=$motor2Inverted', isSystem: true);
    },
    onCustomControlsUpdated: (List<CustomControl> customControls) {
      setState(() {
        _customControls = customControls.where((control) => control.isActive).toList();
      });
      _addToConsole('${customControls.length} contrôles personnalisés mis à jour', isSystem: true);
    },
  );
}

void _reloadCommands() {
  // Cette méthode recharge les commandes depuis SharedPreferences
  // pour s'assurer qu'elles sont à jour
  _loadCommands();
}

void _loadCommands() async {
  final prefs = await SharedPreferences.getInstance();
  final commandsJson = prefs.getString('control_commands');
  if (commandsJson != null) {
    try {
      final commandsMap = Map<String, String>.from(json.decode(commandsJson));
      setState(() {
        _currentCommands = commandsMap;
      });
    } catch (e) {
      print('Erreur chargement commandes: $e');
    }
  }
}
 

  // CORRECTION: Utiliser l'IP et port de la connexion active
void _sendCommand(String command) {
  if (!_isReadyToSend()) {
    _addToConsole('❌ Impossible d\'envoyer: Vérifiez la connexion', isSystem: true, isError: true);
    return;
  }

  if (_connectionType == 'wifi' && widget.wifiManager.hasActiveConnection) {
    final ip = widget.wifiManager.currentIp;
    final port = widget.wifiManager.currentPort;
    
    if (ip == null) {
      _addToConsole('❌ Aucune IP configurée pour WiFi', isSystem: true, isError: true);
      return;
    }

    // Pour WebSocket
    if (widget.wifiManager.getActiveProtocol() == WiFiProtocol.websocket) {
      widget.wifiManager.sendWebSocketMessage(command);
      _addToConsole('➤ WiFi WebSocket: $command');
    } 
    // Pour HTTP
    else {
      widget.wifiManager.sendHttpCommand(
        ip: ip,
        port: port ?? 80, // Port par défaut
        command: command,
        
      );
      _addToConsole('➤ WiFi HTTP: $command vers $ip:${port ?? 80}');
    }
  } 
  else if (_connectionType == 'bluetooth' && widget.bluetoothManager.connectedDevice != null) {
    widget.bluetoothManager.sendCommand(command);
    _addToConsole('➤ Bluetooth: $command');
  } 
  else {
    _addToConsole('❌ Aucune connexion active', isSystem: true, isError: true);
  }
}

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[50],
    appBar: AppBar(
      title: const Text(
        'CONTROL',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 1.5,
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
        // 1. Icône de connexion (WiFi/Bluetooth) avec menu déroulant
        PopupMenuButton<String>(
          icon: Stack(
            children: [
              Icon(
                _connectionType == 'wifi' 
                  ? Icons.wifi 
                  : _connectionType == 'bluetooth' 
                    ? Icons.bluetooth 
                    : Icons.link,
                color: Colors.white,
              ),
              // Indicateur de statut de connexion
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected() ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            ],
          ),
          onSelected: (value) {
            if (value == 'wifi') {
              _openWifiModal();
            } else if (value == 'bluetooth') {
              _openBluetoothModal();
            }
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<String>(
              value: 'wifi',
              child: Row(
                children: [
                  Icon(Icons.wifi, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Connexion WiFi'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'bluetooth',
              child: Row(
                children: [
                  Icon(Icons.bluetooth, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Connexion Bluetooth'),
                ],
              ),
            ),
          ],
          tooltip: 'Choisir le mode de connexion',
        ),

        // 2. Icône appareil (historique de connexion)
        IconButton(
          icon: const Icon(Icons.device_hub, color: Colors.white),
          onPressed: _openDeviceHistory,
          tooltip: 'Historique des appareils',
        ),

        // 3. Icône paramètres
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed:_openSettingsDialog,
          tooltip: 'Paramètres',
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildMotorControlSection(),
                _buildDirectionControlSection(),
                _buildBuzzerControlSection(),
                _buildCustomControlsSection(),
                _buildSensorControlSection(),
              ],
            ),
          ),
        ),
        // Bouton pour afficher/masquer la console
        _buildConsoleToggleButton(),
        // Section console (affichée conditionnellement)
        if (_showConsole) _buildConsoleSection(),
      ],
    ),
  );
}

 // control_widget.dart (inside _ControlWidgetState)

Widget _buildCustomControlsSection() {
  if (_customControls.isEmpty) {
    return const SizedBox.shrink();
  }

  return Card(
    margin: const EdgeInsets.all(16),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'CONTRÔLES PERSONNALISÉS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 16),
          // MODIFICATION: Utilisation de GridView.builder pour l'alignement 3x3
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customControls.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 3 colonnes par ligne
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0, 
            ),
            itemBuilder: (context, index) {
              return _buildCustomControlButton(_customControls[index]);
            },
          ),
        ],
      ),
    ),
  );
}

Widget _buildCustomControlButton(CustomControl control) {
  // Déterminer si la commande OFF est disponible pour activer l'appui long
  final bool hasOffCommand = control.commandOff.isNotEmpty;

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () {
        // Simple tap envoie la commande ON
        final command = control.commandOn.isNotEmpty 
            ? control.commandOn 
            : 'CMD:${control.name}:ON';
        _sendCommand(command);
        _addToConsole('Contrôle personnalisé: ${control.name} - $command (ON)');
      },
      onLongPress: hasOffCommand ? () {
        // Appui long envoie la commande OFF (si commandOff est défini)
        _sendCommand(control.commandOff);
        _addToConsole('Contrôle personnalisé: ${control.name} - ${control.commandOff} (OFF)');
      } : null, // Si pas de commande OFF, l'appui long est désactivé
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: control.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: control.color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getCustomIconData(control.icon),
              color: control.color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              control.name,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: control.color,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // Indication de l'appui long pour OFF
            if (hasOffCommand) 
              Text(
                '(ON/OFF)',
                style: TextStyle(
                  fontSize: 8,
                  color: control.color.withOpacity(0.7),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

IconData _getCustomIconData(String iconName) {
  switch (iconName) {
    case 'touch_app': return Icons.touch_app;
    case 'play_arrow': return Icons.play_arrow;
    case 'stop': return Icons.stop;
    case 'pause': return Icons.pause;
    case 'power_settings_new': return Icons.power_settings_new;
    case 'settings': return Icons.settings;
    case 'build': return Icons.build;
    case 'tune': return Icons.tune;
    case 'speed': return Icons.speed;
    case 'flash_on': return Icons.flash_on;
    case 'highlight': return Icons.highlight;
    case 'bolt': return Icons.bolt;
    case 'ac_unit': return Icons.ac_unit;
    case 'whatshot': return Icons.whatshot;
    case 'gamepad': return Icons.gamepad;
    case 'joystick': return Icons.sports_esports;
    case 'sports_esports': return Icons.sports_esports;
    default: return Icons.touch_app;
  }
}

  Widget _buildConsoleToggleButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue[800],
        border: Border(
          top: BorderSide(color: Colors.blue[900]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'CONSOLE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _showConsole ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: Colors.white,
              size: 20,
            ),
            onPressed: _toggleConsole,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
            tooltip: _showConsole ? 'Masquer la console' : 'Afficher la console',
          ),
        ],
      ),
    );
  }

  Widget _buildMotorControlSection() {
  return Card(
    margin: const EdgeInsets.all(16),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'CONTRÔLE DES MOTEURS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 19, 115, 225),
            ),
          ),
          const SizedBox(height: 16),
          // Moteur 1
          _buildMotorSlider(
            label: 'MOTEUR 1',
            value: _motor1Speed,
            onChanged: _updateMotor1Speed,
            color: Colors.red[400]!,
          ),
          const SizedBox(height: 16),
          // Moteur 2
          _buildMotorSlider(
            label: 'MOTEUR 2',
            value: _motor2Speed,
            onChanged: _updateMotor2Speed,
            color: Colors.green[600]!,
          ),
          const SizedBox(height: 12),
          // Affichage PWM
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PWM: ${(_motor1Speed * 255).toInt()}',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'PWM: ${(_motor2Speed * 255).toInt()}',
                style: TextStyle(
                  color: Colors.green[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Sous-widget pour un slider de moteur
Widget _buildMotorSlider({
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
  required Color color,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Slider(
        value: value,
        onChanged: onChanged,
        min: 0.0,
        max: 1.0,
        divisions: 255,
        label: '${(value * 255).toInt()}',
        activeColor: color,
        inactiveColor: color.withOpacity(0.3),
      ),
    ],
  );
}


  Widget _buildDirectionControlSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'CONTRÔLE DE DIRECTION',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 58, 125, 201),
              ),
            ),
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                // Grille directionnelle
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 1.0,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    // Ligne 1
                    const SizedBox(), // Case vide
                    _buildDirectionButton(
                      icon: Icons.arrow_upward,
                      label: 'AVANT',
                      onTap: () => _sendDirectionCommand('Avant'),
                      color: Colors.green,
                    ),
                    const SizedBox(), // Case vide
                    
                    // Ligne 2
                    _buildDirectionButton(
                      icon: Icons.arrow_back,
                      label: 'GAUCHE',
                      onTap: () => _sendDirectionCommand('Gauche'),
                      color: Colors.orange,
                    ),
                    _buildCenterButton(),
                    _buildDirectionButton(
                      icon: Icons.arrow_forward,
                      label: 'DROITE',
                      onTap: () => _sendDirectionCommand('Droite'),
                      color: Colors.orange,
                    ),
                    
                    // Ligne 3
                    const SizedBox(), // Case vide
                    _buildDirectionButton(
                      icon: Icons.arrow_downward,
                      label: 'ARRIÈRE',
                      onTap: () => _sendDirectionCommand('Arriere'),
                      color: Colors.red,
                    ),
                    const SizedBox(), // Case vide
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _togglePause,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _isPaused ? Colors.green : Colors.orange,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _isPaused ? Icons.play_arrow : Icons.pause,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }

  // control_widget.dart (inside _ControlWidgetState)

 Widget _buildBuzzerControlSection() {
  return Card(
    margin: const EdgeInsets.all(16),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'BUZZER & STATUT CAPTEURS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 32, 121, 223),
            ),
          ),
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Indicateur Ultrasonic 1 & 2
              Column(
                children: [
                  _buildSensorIndicator(
                    icon: Icons.waves,
                    label: 'Ultra 1',
                    isActive: _ultrasonic1Distance > 0 && _ultrasonic1Distance < 50, // Exemple: actif si distance < 50cm
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 12),
                 
                ],
              ),

              // 2. Bouton de Bascule du Buzzer
              _buildBuzzerToggle(), 

              // 3. Indicateur PIR
              _buildSensorIndicator(
                icon: Icons.person_search,
                label: 'PIR',
                isActive: _pirDetected,
                color: Colors.deepOrange,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildBuzzerToggle() {
  Color color;
  IconData icon;
  String label;

  if (_buzzerState == 1) { // ON
    color = Colors.green;
    icon = Icons.notifications_active;
    label = 'ACTIF';
  } else if (_buzzerState == 2) { // PAUSE
    color = Colors.orange;
    icon = Icons.pause_circle_filled;
    label = 'PAUSE';
  } else { // OFF
    color = Colors.red;
    icon = Icons.notifications_off;
    label = 'ARRÊT';
  }

  return Column(
    children: [
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleBuzzerState,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
          fontSize: 12,
        ),
      ),
    ],
  );
}

// Nouveau sous-widget pour afficher l'indicateur des capteurs
Widget _buildSensorIndicator({
  required IconData icon,
  required String label,
  required bool isActive,
  required Color color,
}) {
  return Column(
    children: [
      Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.8) : Colors.grey[300],
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? color : Colors.grey[400]!,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.grey[600],
          size: 30,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isActive ? color : Colors.grey,
          fontSize: 12,
        ),
      ),
    ],
  );
}

 Widget _buildSensorControlSection() {
  return Card(
    margin: const EdgeInsets.all(16),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DONNÉES CAPTEURS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 16),
          // Ultrasonic 1
          _buildSensorDisplay(
            icon: Icons.waves,
            label: 'Ultrasonic 1 (avant)',
            // Affichage de la distance avec une décimale, simulant une lecture
            value: '${_ultrasonic1Distance.toStringAsFixed(1)} cm', 
            color: Colors.blueAccent,
          ),
          
          const SizedBox(height: 8),
          // PIR
          _buildSensorDisplay(
            icon: Icons.person_search,
            label: 'Capteur PIR (Mouvement)',
            value: _pirDetected ? 'Mouvement détecté' : 'Clair',
            color: _pirDetected ? Colors.deepOrange : Colors.green,
          ),
        ],
      ),
    ),
  );
}

// Sous-widget pour afficher les données d'un capteur
Widget _buildSensorDisplay({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Row(
    children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );
}

  Widget _buildConsoleSection() {
  return ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: 200, // Hauteur minimale réduite
      maxHeight: 400, // Hauteur maximale réduite
    ),
    child: Card(
      margin: const EdgeInsets.all(16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // En-tête console
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'CONSOLE DE COMMUNICATION',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear_all, color: Colors.white, size: 20),
                  onPressed: _clearConsole,
                  tooltip: 'Effacer la console',
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                  onPressed: () {
                    if (_commandHistory.isNotEmpty) {
                      final text = _commandHistory.map((log) => log.toString()).join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      _addToConsole('Console copiée dans le presse-papier', isSystem: true);
                    }
                  },
                  tooltip: 'Copier la console',
                ),
              ],
            ),
          ),
          
          // Contenu console
          Expanded(
            child: Container(
              color: Colors.black87,
              child: _commandHistory.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucune communication\nLes commandes apparaîtront ici',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _consoleController,
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: _commandHistory.length,
                      itemBuilder: (context, index) {
                        return _buildConsoleItem(_commandHistory[index]);
                      },
                    ),
            ),
          ),
          
          // Statut connexion
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _connectionType == 'wifi' ? Icons.wifi : Icons.bluetooth,
                  color: Colors.green,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Connecté via ${_connectionType.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_commandHistory.length} messages',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildConsoleItem(CommandLog log) {
  // DÉTERMINER LE STYLE EN FONCTION DU TYPE DE MESSAGE
  TextStyle textStyle;
  if (log.isError) {
    textStyle = TextStyle(
      color: Colors.red[800],
      fontSize: 14,
    );
  } else if (log.isDeviceResponse) {
    // STYLE SPÉCIAL POUR LES RÉPONSES DU MICROCONTRÔLEUR
    textStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: Colors.blue[700], // Bleu pour les réponses
      fontSize: 14,
    );
  } else if (log.isSystem) {
    textStyle = TextStyle(
      color: Colors.blue[600],
      fontSize: 14,
    );
  } else {
    textStyle = TextStyle(
      color: Colors.grey[800],
      fontSize: 14,
    );
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: log.isError 
          ? Colors.red[50] 
          : log.isSystem 
              ? Colors.blue[50] 
              : log.isDeviceResponse
                  ? Colors.blue[50] // Fond bleu clair pour les réponses
                  : Colors.grey[50],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: log.isError 
            ? Colors.red[100]! 
            : log.isSystem 
                ? Colors.blue[100]! 
                : log.isDeviceResponse
                    ? Colors.blue[200]! // Bordure bleue pour les réponses
                    : Colors.grey[200]!,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          log.isError ? Icons.error 
            : log.isDeviceResponse ? Icons.memory // Icône puce pour microcontrôleur
            : Icons.info,
          color: log.isError ? Colors.red 
                : log.isDeviceResponse ? Colors.blue[700] // Icône bleue pour les réponses
                : Colors.blue,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                log.message,
                style: textStyle, // APPLIQUER LE STYLE APPROPRIÉ
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(log.timestamp),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

 class CommandLog {
  final String message;
  final DateTime timestamp;
  final bool isSystem;
  final bool isError;
  final bool isDeviceResponse; // NOUVEAU CHAMP

  CommandLog({
    required this.message,
    required this.timestamp,
    this.isSystem = false,
    this.isError = false,
    this.isDeviceResponse = false, // VALEUR PAR DÉFAUT
  });

  @override
  String toString() {
    return '${_formatTime(timestamp)} $message';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}