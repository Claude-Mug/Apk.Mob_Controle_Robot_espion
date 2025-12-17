// vocal_widget.dart - VERSION COMPLÈTE AVEC CONNEXIONS RÉELLES

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lali_project/services/Services.Wifi.dart';
import 'package:lali_project/services/blue_manager.dart';
import 'package:lali_project/modal_connexion/bluetooth.dart';
import 'package:lali_project/modal_connexion/wifi.dart';
import 'package:lali_project/stockage/devices.dart';
import 'package:lali_project/parametres/Vocal.dart';

class VocalWidget extends StatefulWidget {
  final BluetoothManager bluetoothManager;
  final WiFiControlManager wifiManager;
  
  const VocalWidget({
    Key? key,
    required this.bluetoothManager,
    required this.wifiManager,
  }) : super(key: key);

  @override
  State<VocalWidget> createState() => _VocalWidgetState();
}

class _VocalWidgetState extends State<VocalWidget> {
  // Paramètres vocaux
  VocalNormalizationSettings _vocalSettings = VocalNormalizationSettings.defaultSettings();
  // Gestion de la reconnaissance vocale
  final stt.SpeechToText _speech = stt.SpeechToText();
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();
  
  bool _isListening = false;
  String _recognizedText = '';
  String _currentText = '';
  bool _speechAvailable = false;

  // Historique des commandes
  final List<CommandLog> _commandHistory = [];

  // État de connexion
  String _connectionMode = "none"; // "none", "wifi", "bluetooth"
  String _connectionStatus = "Mode démo";
  String _connectedDeviceName = "Aucun appareil";

  // Contrôleur pour la console
  final ScrollController _consoleController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initSpeechRecognition();
    _setupDeviceResponseListener();
    _deviceHistoryManager.loadHistory();
    _addToConsole('Système de reconnaissance vocale initialisé', isSystem: true);
  }

  // Initialisation de la reconnaissance vocale
  Future<void> _initSpeechRecognition() async {
  try {
    PermissionStatus status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _showError('Permission microphone non accordée');
      return;
    }

    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        print('🔍 Statut reconnaissance: $status');
        setState(() {
          if (status == 'listening') {
            _isListening = true;
          } else if (status == 'notListening' && _isListening) {
            _isListening = false;
            // NE PAS appeler _processFinalCommand ici
            // Laisser onResult gérer le résultat final
          }
        });
      },
      onError: (error) {
        setState(() {
          _isListening = false;
        });
        _showError('Erreur reconnaissance: $error');
        _addToConsole('Erreur reconnaissance: $error', isSystem: true, isError: true);
      },
    );

    if (!_speechAvailable) {
      _showError('Reconnaissance vocale non disponible sur cet appareil');
      _addToConsole('Reconnaissance vocale non disponible', isSystem: true, isError: true);
    } else {
      _addToConsole('Reconnaissance vocale initialisée avec succès', isSystem: true);
    }
  } catch (e) {
    _showError('Impossible d\'initialiser la reconnaissance vocale: $e');
    _addToConsole('Erreur initialisation reconnaissance: $e', isSystem: true, isError: true);
  }
}

  // Démarrer l'écoute
  void _startListening() async {
  if (!_speechAvailable) {
    _showError('Reconnaissance vocale non disponible');
    _addToConsole('❌ Reconnaissance vocale non disponible', isError: true);
    return;
  }

  PermissionStatus status = await Permission.microphone.request();
  if (status != PermissionStatus.granted) {
    _showError('Permission microphone requise');
    _addToConsole('❌ Permission microphone refusée', isError: true);
    return;
  }

  setState(() {
    _currentText = '';
    _recognizedText = '';
  });

  try {
    await _speech.listen(
      onResult: (result) {
        print('🔍 Résultat reconnaissance: ${result.recognizedWords} (final: ${result.finalResult})');
        
        setState(() {
          if (result.finalResult) {
            _currentText = _normalizeCommand(result.recognizedWords);
            _recognizedText = _currentText;
            _addToConsole('🎤 Commande finale détectée: "$_currentText"');
            // Traiter immédiatement le résultat final
            _processFinalCommand();
          } else {
            _currentText = result.recognizedWords;
            if (result.recognizedWords.isNotEmpty && 
                result.recognizedWords != 'J\'écoute...') {
              _addToConsole('... Reconnaissance partielle: "${result.recognizedWords}"', 
                          isSystem: true);
            }
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      localeId: 'fr_FR',
    );
    
    _addToConsole('🎤 Début de l\'écoute vocale - Parlez maintenant...', isSystem: true);
    
  } catch (e) {
    _showError('Erreur lors du démarrage de l\'écoute: $e');
    _addToConsole('❌ Erreur démarrage écoute: $e', isSystem: true, isError: true);
  }
}

// 6. Nouvelle méthode pour écouter les réponses du microcontrôleur
 void _setupDeviceResponseListener() {
  // Écouter les réponses WiFi WebSocket
  widget.wifiManager.webSocketMessages.listen((message) {
    _addToConsole('📡 Réponse ESP32: $message', isDeviceResponse: true);
    _showSuccess('Réception: $message');
  });

  // Écouter les statuts de connexion WebSocket
  widget.wifiManager.isWebSocketConnected.listen((isConnected) {
    if (isConnected) {
      _addToConsole('✅ WebSocket connecté', isSystem: true);
    } else {
      _addToConsole('⚠️ WebSocket déconnecté', isSystem: true);
    }
  });

  // Écouter les réponses HTTP (polling)
  widget.wifiManager.httpPollingMessages.listen((result) {
    if (result.success) {
      _addToConsole('📡 Réponse HTTP: ${result.message}', isDeviceResponse: true);
    } else {
      _addToConsole('❌ Erreur HTTP: ${result.message}', isError: true);
    }
  });

  // Écouter les changements de connectivité WiFi
  widget.wifiManager.wifiConnectivityStream.listen((status) {
    _addToConsole('📶 Statut réseau: $status', isSystem: true);
    _updateConnectionStatus();
  });

  // Écouter les réponses Bluetooth (à adapter selon votre BluetoothManager)
  // Exemple hypothétique :
  // widget.bluetoothManager.responseStream?.listen((response) {
  //   _addToConsole('📱 Réponse Bluetooth: $response', isDeviceResponse: true);
  // });
}

@override
void dispose() {
  // Nettoyer les listeners et connexions
  _speech.stop();
  _consoleController.dispose();
  
  // Déconnecter toutes les connexions WiFi
  widget.wifiManager.disconnectAllConnections();
  
  super.dispose();
}

  // Arrêter l'écoute
  void _stopListening() async {
  try {
    // Sauvegarder le texte courant avant d'arrêter
    final String finalText = _currentText.isNotEmpty ? _currentText : _recognizedText;
    
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
    
    // Attendre un peu pour que le dernier résultat soit traité
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Utiliser le texte sauvegardé
    if (finalText.isNotEmpty && finalText != 'J\'écoute...') {
      setState(() {
        _currentText = finalText;
        _recognizedText = finalText;
      });
      _processFinalCommand();
    }
    
    _addToConsole('⏹️ Arrêt de l\'écoute vocale', isSystem: true);
  } catch (e) {
    _showError('Erreur lors de l\'arrêt de l\'écoute');
    _addToConsole('Erreur arrêt écoute: $e', isSystem: true, isError: true);
  }
}

  // Traiter la commande finale
  void _processFinalCommand() {
  if (_currentText.isNotEmpty && _currentText != 'J\'écoute...') {
    final normalizedText = _normalizeCommand(_currentText);
    setState(() {
      _recognizedText = normalizedText;
    });
    
    // Ajouter à l'historique AVANT envoi
    _addToConsole('🎤 Commande vocale détectée: "$normalizedText"');
    
    // Vérifier la connexion avant d'envoyer
    if (_isConnected()) {
      // Envoyer la commande réelle
      _addToConsole('✅ Connexion active - Envoi de la commande...', isSystem: true);
      _sendVoiceCommand(normalizedText);
    } else {
      _addToConsole('❌ Impossible d\'envoyer - Aucune connexion active', isError: true);
      _showError('Impossible d\'envoyer la commande. Veuillez vous connecter à un appareil.');
    }
  }
}

  // Normaliser la commande
  String _normalizeCommand(String text) {
  // Charger les paramètres au besoin
  if (!_vocalSettings.enableNormalization) {
    return text.trim();
  }
  
  return _vocalSettings.normalizeText(text);
}

  void _openVocalSettings() async {
  _addToConsole('⚙️ Ouverture des paramètres vocaux...', isSystem: true);
  
  await VocalSettings.showModal(
    context: context,
    onSettingsChanged: (newSettings) {
      setState(() {
        _vocalSettings = newSettings;
      });
      _addToConsole('✅ Paramètres vocaux mis à jour', isSystem: true);
    },
  );
}

// Analyser et envoyer la commande vocale
 void _sendVoiceCommand(String command) {
  String processedCommand = command.trim();
  
  print('🔍 [_sendVoiceCommand] Début - Commande: "$processedCommand"');
  
  if (processedCommand.isEmpty) {
    _addToConsole('❌ Commande vide - Aucun texte à envoyer', isError: true);
    _showError('Commande vocale vide');
    return;
  }

  // Vérifier la connexion AVANT d'envoyer
  if (!_isConnected()) {
    _addToConsole('❌ Envoi impossible - Aucune connexion active', isError: true);
    _showError('Impossible d\'envoyer. Veuillez vous connecter à un appareil.');
    return;
  }

  try {
    print('🔍 [_sendVoiceCommand] Tentative d\'envoi: "$processedCommand"');
    
    // AFFICHER LA COMMANDE ENVOYÉE AVEC LE NOUVEAU STYLE
    _addToConsole('Envoi de la commande: "$processedCommand"', isSentCommand: true);
    
    // ENVOYER LA COMMANDE
    _sendCommand(processedCommand);
    
    _addToConsole('✅ Commande envoyée avec succès: "$processedCommand"');
    _showSuccess('Commande envoyée: "$processedCommand"');
    
  } catch (e) {
    print('❌ [_sendVoiceCommand] Erreur: $e');
    _addToConsole('❌ Erreur lors de l\'envoi: $e', isError: true);
    _showError('Erreur d\'envoi: $e');
  }
}

  // Méthodes de connexion Bluetooth
  void _openBluetoothModal() async {
    _addToConsole('📱 Ouverture du sélecteur Bluetooth...', isSystem: true);
    
    try {
      await BluetoothModal.show(
        context: context,
        manager: widget.bluetoothManager,
        onDeviceSelected: (device) {
          final deviceName = device.name ?? 'Appareil Bluetooth';
          _addToConsole('✅ Appareil Bluetooth sélectionné: $deviceName', isSystem: true);
          
          // Ajouter à l'historique des appareils
          _deviceHistoryManager.addDevice(DeviceHistory(
            name: deviceName,
            address: device.address,
            connectionType: 'bluetooth',
            lastConnected: DateTime.now(),
          ));
          
          setState(() {
            _connectionMode = 'bluetooth';
            _connectionStatus = 'Connecté via Bluetooth';
            _connectedDeviceName = deviceName;
          });
          _updateConnectionStatus();
          _addToConsole('🔄 Mode de connexion changé: BLUETOOTH', isSystem: true);
        },
      );
    } catch (e) {
      _addToConsole('❌ Erreur modal Bluetooth: $e', isSystem: true, isError: true);
    }
  }

  // Méthodes de connexion WiFi
  void _openWifiModal() async {
    _addToConsole('📶 Ouverture du sélecteur WiFi...', isSystem: true);
    
    try {
      await WifiConnectionModal.show(
        context: context,
        manager: widget.wifiManager,
      );
      
      // Vérifier si la connexion WiFi a réussi
      if (widget.wifiManager.hasActiveConnection) {
        _addToConsole('✅ Configuration WiFi terminée', isSystem: true);
        
        // Ajouter à l'historique des appareils
        _deviceHistoryManager.addDevice(DeviceHistory(
          name: 'Connexion WiFi',
          address: widget.wifiManager.connectionStatus,
          connectionType: 'wifi',
          lastConnected: DateTime.now(),
        ));
        
        setState(() {
          _connectionMode = 'wifi';
          _connectionStatus = 'Connecté via WiFi';
          _connectedDeviceName = widget.wifiManager.connectionStatus;
        });
        _updateConnectionStatus();
        _addToConsole('🔄 Mode de connexion changé: WIFI', isSystem: true);
      }
    } catch (e) {
      _addToConsole('❌ Erreur modal WiFi: $e', isSystem: true, isError: true);
    }
  }

  void _openDeviceHistory() {
    DeviceHistoryModal.show(
      context: context,
      manager: _deviceHistoryManager,
      onReconnect: (device) {
        _addToConsole('🔄 Tentative de reconnexion à ${device.name}', isSystem: true);
        
        if (device.connectionType == 'bluetooth') {
          // Logique pour reconnecter en Bluetooth
          _addToConsole('📱 Reconnexion Bluetooth à ${device.name}', isSystem: true);
          // Ici vous devrez implémenter la reconnexion Bluetooth spécifique
        } else if (device.connectionType == 'wifi') {
          // Logique pour reconnecter en WiFi
          _addToConsole('📶 Reconnexion WiFi à ${device.name}', isSystem: true);
          // Ici vous devrez implémenter la reconnexion WiFi spécifique
        }
        
        setState(() {
          _connectionMode = device.connectionType;
          _connectionStatus = 'Connecté via ${device.connectionType.toUpperCase()}';
          _connectedDeviceName = device.name;
        });
      },
    );
  }

  // Vérifier si une connexion est active
  // Remplacer la méthode _isConnected() existante par :
bool _isConnected() {
  bool connected = false;
  
  if (_connectionMode == 'wifi') {
    connected = widget.wifiManager.hasActiveConnection;
  } else if (_connectionMode == 'bluetooth') {
    connected = widget.bluetoothManager.connectedDevice != null;
  }
  
  return connected;
}

// Ajouter une méthode pour mettre à jour le statut de connexion
void _updateConnectionStatus() {
  bool connected = _isConnected();
  
  setState(() {
    if (connected) {
      _connectionStatus = 'Connecté via ${_connectionMode.toUpperCase()}';
      // Mettre à jour le nom de l'appareil connecté
      if (_connectionMode == 'bluetooth') {
        _connectedDeviceName = widget.bluetoothManager.connectedDevice?.name ?? 'Appareil Bluetooth';
      } else if (_connectionMode == 'wifi') {
        _connectedDeviceName = widget.wifiManager.connectionStatus;
      }
    } else {
      _connectionStatus = 'Déconnecté - Mode démo';
      _connectedDeviceName = 'Aucun appareil connecté';
    }
  });
}
  // Envoyer une commande via la connexion active
  void _sendCommand(String command) {
  print('🔍 [_sendCommand] Début - Mode: $_connectionMode, Commande: $command');
  
  if (_connectionMode == 'wifi' && widget.wifiManager.hasActiveConnection) {
    print('🔍 [_sendCommand] Envoi via WiFi');
    
    final ip = widget.wifiManager.currentIp;
    final port = widget.wifiManager.currentPort;
    
    if (ip == null) {
      _addToConsole('❌ Aucune IP configurée pour WiFi', isSystem: true, isError: true);
      return;
    }

    if (widget.wifiManager.getActiveProtocol() == WiFiProtocol.websocket) {
      print('🔍 [_sendCommand] Envoi WebSocket');
      widget.wifiManager.sendWebSocketMessage(command);
      _addToConsole('📡 Envoi via WiFi WebSocket: "$command"', isSentCommand: true);
      
      // Attendre une réponse
      Future.delayed(Duration(seconds: 2), () {
        _addToConsole('⏳ En attente de réponse...', isSystem: true);
      });
      
    } else {
      print('🔍 [_sendCommand] Envoi HTTP vers $ip:${port ?? 80}');
      
      // Pour HTTP, on peut attendre la réponse directement
      widget.wifiManager.sendHttpCommand(
        ip: ip,
        port: port ?? 80,
        command: command,
      ).then((result) {
        if (result.success) {
          _addToConsole('✅ Commande exécutée avec succès', isSystem: true);
        } else {
          _addToConsole('❌ Erreur: ${result.message}', isError: true);
        }
      });
      
      _addToConsole('📡 Envoi via WiFi HTTP: "$command" vers $ip:${port ?? 80}', isSentCommand: true);
    }
    
  } else if (_connectionMode == 'bluetooth' && widget.bluetoothManager.connectedDevice != null) {
    print('🔍 [_sendCommand] Envoi Bluetooth');
    widget.bluetoothManager.sendCommand(command);
    _addToConsole('📱 Envoi via Bluetooth: "$command"', isSentCommand: true);
    
  } else {
    print('❌ [_sendCommand] Aucune connexion active');
    _addToConsole('❌ Aucune connexion active - Commande non envoyée', isSystem: true, isError: true);
    _showError('Aucune connexion active. Veuillez vous connecter à un appareil.');
  }
}

  // Gestion de la console
  void _addToConsole(String message, {
  bool isSystem = false, 
  bool isError = false, 
  bool isDeviceResponse = false,
  bool isSentCommand = false // NOUVEAU PARAMÈTRE
}) {
  String prefix = '';
  if (isDeviceResponse) {
    prefix = '📟 ';
  } else if (isError) {
    prefix = '❌ ';
  } else if (isSystem) {
    prefix = '⚙️ ';
  } else if (isSentCommand) {
    prefix = '➤ '; // Icône pour les commandes envoyées
  }
  
  final formattedMessage = prefix + message;
  
  setState(() {
    _commandHistory.insert(0, CommandLog(
      message: formattedMessage,
      timestamp: DateTime.now(),
      isSystem: isSystem,
      isError: isError,
      isDeviceResponse: isDeviceResponse,
      isSentCommand: isSentCommand, // ASSIGNER LA VALEUR
    ));
    
    if (_commandHistory.length > 100) {
      _commandHistory.removeLast();
    }
  });
  
  // Auto-scroll
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

  void _clearConsole() {
    setState(() {
      _commandHistory.clear();
    });
    _addToConsole('🧹 Console effacée', isSystem: true);
    _showSuccess('Console effacée');
  }

  // Afficher un message d'erreur
  void _showError(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  // Afficher un message de succès
  void _showSuccess(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[100], // Fond gris clair
    appBar: AppBar(
      title: const Text(
        'Commande Vocale',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.blue[700], // AppBar en bleu
      elevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.devices, color: Colors.white),
          onPressed: _openDeviceHistory,
          tooltip: 'Historique des appareils',
        ),
        IconButton(
          icon: Stack(
            children: [
              Icon(
                _connectionMode == "wifi"
                    ? Icons.wifi
                    : _connectionMode == "bluetooth"
                        ? Icons.bluetooth
                        : Icons.cloud,
                color: _connectionMode == "none" ? Colors.grey[300] : Colors.white,
              ),
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
          onPressed: () async {
            final choix = await showMenu<String>(
              context: context,
              position: const RelativeRect.fromLTRB(1000, 80, 10, 100),
              items: [
                const PopupMenuItem(
                  value: "wifi",
                  child: Row(
                    children: [
                      Icon(Icons.wifi, color: Colors.blue),
                      SizedBox(width: 8),
                      Text("Connexion Wi-Fi"),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: "bluetooth",
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth, color: Colors.blue),
                      SizedBox(width: 8),
                      Text("Connexion Bluetooth"),
                    ],
                  ),
                ),
              ],
            );

            if (choix != null) {
              if (choix == "wifi") {
                _openWifiModal();
              } else {
                _openBluetoothModal();
              }
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: _openVocalSettings,
          tooltip: 'Paramètres',
        ),
      ],
    ),
    body: Column(
      children: [
        _buildStatusHeader(),
        _buildMicrophoneButton(),
        Expanded(
          child: _buildConsole(),
        ),
      ],
    ),
  );
}

  // En-tête de statut
  Widget _buildStatusHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isConnected() ? Colors.green[50] : Colors.orange[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected() ? Icons.check_circle : Icons.info,
            color: _isConnected() ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _connectionStatus,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _connectedDeviceName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (!_isConnected())
            TextButton(
              onPressed: () {
                _showConnectionDialog();
              },
              child: const Text('CONNECTER'),
            ),
        ],
      ),
    );
  }
  
  // Console en temps réel
  Widget _buildConsole() {
  return Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      children: [
        // En-tête de la console
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Console des Commandes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.clear_all, size: 20),
                onPressed: _clearConsole,
                tooltip: 'Effacer',
              ),
            ],
          ),
        ),
        
        // Contenu de la console
        Expanded(
          child: _commandHistory.isEmpty
              ? _buildEmptyConsole()
              : ListView.builder(
                  controller: _consoleController,
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: _commandHistory.length,
                  itemBuilder: (context, index) {
                    final log = _commandHistory[index];
                    return _buildConsoleItem(log);
                  },
                ),
        ),
      ],
    ),
  );
}

  // Bouton microphone principal
  Widget _buildMicrophoneButton() {
  return Container(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        // Bouton microphone simplifié
        GestureDetector(
          onTapDown: (_) => _startListening(),
          onTapUp: (_) => _stopListening(),
          onTapCancel: _stopListening,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _isListening ? Colors.blue[500] : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(
                color: _isListening ? Colors.blue : Colors.grey[300]!,
                width: 3,
              ),
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.white : Colors.blue,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isListening ? 'Parlez maintenant...' : 'Appuyez pour parler',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Commandes vocales',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            _addToConsole('🧪 TEST: Envoi commande manuelle', isSystem: true);
            _sendCommand('TEST_COMMANDE');
          },
          child: Text('TEST ENVOI'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
        ),
      ],
      
    ),
  );
}

  Widget _buildEmptyConsole() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.terminal, color: Colors.grey[300], size: 48),
        const SizedBox(height: 16),
        Text(
          'Aucune commande',
          style: TextStyle(
            color: Colors.grey[500],
          ),
        ),
        Text(
          'Les commandes vocales apparaîtront ici',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
  
  Widget _buildConsoleItem(CommandLog log) {
  // DÉTERMINER LE STYLE EN FONCTION DU TYPE DE MESSAGE
  TextStyle textStyle;
  if (log.isSentCommand) {
    textStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.blue[800],
      fontSize: 16, // Police plus grande
    );
  } else if (log.isError) {
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
              : log.isSentCommand
                  ? Colors.blue[50] // Fond bleu clair pour les commandes envoyées
                  : log.isDeviceResponse
                      ? Colors.blue[50] // Fond bleu clair pour les réponses
                      : Colors.grey[50],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: log.isError 
            ? Colors.red[100]! 
            : log.isSystem 
                ? Colors.blue[100]! 
                : log.isSentCommand
                    ? Colors.blue[200]! // Bordure bleue pour les commandes envoyées
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
            : log.isSentCommand ? Icons.send // Icône d'envoi pour les commandes
            : log.isDeviceResponse ? Icons.memory // Icône puce pour microcontrôleur
            : Icons.info,
          color: log.isError ? Colors.red 
                : log.isSentCommand ? Colors.blue[800] // Icône bleue pour les commandes
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

  // Dialogue de connexion
  void _showConnectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paramètres de connexion'),
        content: const Text(
          'Choisissez le mode de connexion pour contrôler votre appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openWifiModal();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, color: Colors.blue),
                SizedBox(width: 8),
                Text('WiFi'),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openBluetoothModal();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth, color: Colors.blue),
                SizedBox(width: 8),
                Text('Bluetooth'),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

// Modèle pour les logs de console
class CommandLog {
  final String message;
  final DateTime timestamp;
  final bool isSystem;
  final bool isError;
  final bool isDeviceResponse;
  final bool isSentCommand; // NOUVEAU CHAMP

  CommandLog({
    required this.message,
    required this.timestamp,
    this.isSystem = false,
    this.isError = false,
    this.isDeviceResponse = false,
    this.isSentCommand = false, // VALEUR PAR DÉFAUT
  });

  @override
  String toString() {
    return '${_formatTime(timestamp)} $message';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}