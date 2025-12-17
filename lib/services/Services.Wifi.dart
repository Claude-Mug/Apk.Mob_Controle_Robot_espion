// lib/Wifi/wifi_communication_manager.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

// Importations des services
import 'package:lali_project/connexion/Wifi/http.dart';
import 'package:lali_project/connexion/Wifi/websocket.dart';
import 'package:lali_project/connexion/Wifi/connectivity.dart';
import 'package:lali_project/connexion/Wifi/network_info.dart';

enum ConnectionMode {
  wifi,
  hotspot,
  unknown,
}

enum WiFiProtocol {
  http,
  websocket,
  none,
}

// Type de microcontrôleur détecté
enum MicrocontrollerType {
  direct,      // WiFi.h + WiFiServer (commandes directes: /COMMANDE)
  parameter,   // WebServer.h (commandes paramétrées: /cmd?c=COMMANDE)
  auto,        // Détection automatique
  unknown
}

enum ConnectionErrorType {
  none,
  invalidIpOrPort,
  wifiNotConnected,
  hotspotNotActive,
  connectionFailed,
  protocolError,
  timeout,
  dnsLookupFailed,
  sslError,
  unauthorized,
  forbidden,
  notFound,
  serverError,
  unknown,
}

typedef ConnectionResult = ({
  bool success,
  String message,
  ConnectionErrorType errorType,
  ConnectionMode connectionMode
});

class WiFiControlManager {
  final ConnectivityService _connectivityService = ConnectivityService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final HttpService _httpService = HttpService();
  final WebSocketService _webSocketService = WebSocketService();

  WiFiProtocol _activeProtocol = WiFiProtocol.none;
  String? _currentIpAddress;
  int? _currentPort;
  ConnectionMode _currentConnectionMode = ConnectionMode.unknown;
  MicrocontrollerType _microcontrollerType = MicrocontrollerType.auto;

  // Cache pour mémoriser le type détecté par IP
  final Map<String, MicrocontrollerType> _typeCache = {};

  // Gestion de la reconnexion WebSocket
  Timer? _reconnectTimer;
  final int _maxRetries = 3;
  int _currentRetries = 0;

  // Timestamp de la dernière commande réussie
  DateTime? _lastSuccessfulCommandTime;

  bool get isConnectedToDevice {
    if (_activeProtocol == WiFiProtocol.websocket) {
      return _webSocketService.currentIsConnected;
    }
    return _currentIpAddress != null && _activeProtocol == WiFiProtocol.http;
  }

  ConnectionMode get currentConnectionMode => _currentConnectionMode;

  // Getters pour l'état de connexion
  bool get hasActiveConnection => _currentIpAddress != null && _activeProtocol != WiFiProtocol.none;
  String? get currentIp => _currentIpAddress;
  int? get currentPort => _currentPort;
  bool get isConnected => hasActiveConnection;

  // Getter pour le statut de connexion formaté
  String get connectionStatus {
    if (!hasActiveConnection) return "Non connecté";
    
    final mode = _currentConnectionMode == ConnectionMode.wifi ? "Wi-Fi" : "Hotspot";
    final protocol = _activeProtocol == WiFiProtocol.websocket ? "WebSocket" : "HTTP";
    
    return "Connecté $protocol ($mode)";
  }

  // Streams
  Stream<List<ConnectivityResult>> get wifiConnectivityStream => _connectivityService.connectionStream;
  Stream<({bool success, String message})> get httpPollingMessages => _httpService.pollingMessages;
  Stream<String> get webSocketMessages => _webSocketService.messages;
  Stream<bool> get isWebSocketConnected => _webSocketService.isConnected;

  WiFiControlManager() {
    _connectivityService.connectionStream.listen((status) {
      if (!status.contains(ConnectivityResult.wifi)) {
        print('WiFiControlManager: Statut WiFi changé: $status');
        // Ne pas déconnecter immédiatement, laisser une chance au hotspot
      }
    });

    _webSocketService.isConnected.listen((isConnected) {
      if (_activeProtocol == WiFiProtocol.websocket && !isConnected) {
        print('WebSocket déconnecté. Tentative de reconnexion...');
        _attemptWebSocketReconnect();
      }
    });
  }

  /// Vérifie si la connexion est toujours valide
  Future<bool> isConnectionValid() async {
    if (!hasActiveConnection) {
      return false;
    }

    // Pour WebSocket, vérifier l'état de connexion
    if (_activeProtocol == WiFiProtocol.websocket) {
      return _webSocketService.currentIsConnected;
    }

    // Pour HTTP, vérifier la validité de la dernière commande
    if (_activeProtocol == WiFiProtocol.http) {
      if (_lastSuccessfulCommandTime == null) {
        return false;
      }
      
      final now = DateTime.now();
      final timeSinceLastSuccess = now.difference(_lastSuccessfulCommandTime!);
      return timeSinceLastSuccess <= Duration(seconds: 10);
    }

    return false;
  }

  /// Test de connexion active vers le device
  Future<ConnectionResult> testDeviceConnection() async {
    if (!hasActiveConnection) {
      return (
        success: false,
        message: 'Aucune connexion active',
        errorType: ConnectionErrorType.connectionFailed,
        connectionMode: _currentConnectionMode
      );
    }

    try {
      if (_activeProtocol == WiFiProtocol.http) {
        // Test HTTP avec une requête simple
        final testResult = await _httpService.testConnection(
          ip: _currentIpAddress!, 
          port: _currentPort ?? 80
        );
        
        if (testResult.success) {
          _lastSuccessfulCommandTime = DateTime.now();
          return (
            success: true,
            message: 'Connexion HTTP vérifiée',
            errorType: ConnectionErrorType.none,
            connectionMode: _currentConnectionMode
          );
        } else {
          return (
            success: false,
            message: 'Échec du test de connexion HTTP: ${testResult.message}',
            errorType: ConnectionErrorType.connectionFailed,
            connectionMode: _currentConnectionMode
          );
        }
      } else if (_activeProtocol == WiFiProtocol.websocket) {
        // Pour WebSocket, l'état est déjà géré par le service
        if (_webSocketService.currentIsConnected) {
          return (
            success: true,
            message: 'Connexion WebSocket active',
            errorType: ConnectionErrorType.none,
            connectionMode: _currentConnectionMode
          );
        } else {
          return (
            success: false,
            message: 'WebSocket déconnecté',
            errorType: ConnectionErrorType.connectionFailed,
            connectionMode: _currentConnectionMode
          );
        }
      }
    } catch (e) {
      return (
        success: false,
        message: 'Erreur lors du test de connexion: ${e.toString()}',
        errorType: ConnectionErrorType.connectionFailed,
        connectionMode: _currentConnectionMode
      );
    }

    return (
      success: false,
      message: 'Protocole non supporté',
      errorType: ConnectionErrorType.protocolError,
      connectionMode: _currentConnectionMode
    );
  }

  /// Détermine le mode de connexion actuel - VERSION CORRIGÉE
  Future<ConnectionMode> determineConnectionMode() async {
    try {
      final connectivity = await _connectivityService.getCurrentConnection();
      final hasWifi = connectivity.contains(ConnectivityResult.wifi);
      
      if (!hasWifi) {
        // Si pas de WiFi, vérifier si on a une IP locale (hotspot)
        final localIp = await _networkInfoService.getLocalIp();
        if (localIp != null && localIp.isNotEmpty) {
          print('🔍 Mode Hotspot détecté - IP locale: $localIp');
          return ConnectionMode.hotspot;
        }
        return ConnectionMode.unknown;
      }
      
      // Si WiFi actif, déterminer le type
      final localIp = await _networkInfoService.getLocalIp();
      if (localIp != null && localIp.isNotEmpty) {
        // Vérifier si c'est une IP de hotspot typique
        if (localIp.startsWith('192.168.43.') || 
            localIp.startsWith('192.168.44.') ||
            localIp.startsWith('192.168.4.') ||
            localIp.startsWith('10.0.0.') ||
            localIp.startsWith('10.141.') ||
            localIp.startsWith('10.101.')) {
          print('🔍 Mode Hotspot détecté via IP: $localIp');
          return ConnectionMode.hotspot;
        }
        print('🔍 Mode Wi-Fi détecté - IP locale: $localIp');
        return ConnectionMode.wifi;
      }
      return ConnectionMode.unknown;
    } catch (e) {
      print('❌ Erreur détermination mode: $e');
      return ConnectionMode.unknown;
    }
  }

  /// Vérification de la connectivité WiFi/Hotspot - VERSION CORRIGÉE
  Future<({bool isConnected, ConnectionMode mode})> checkWifiConnectivity() async {
    try {
      final mode = await determineConnectionMode();
      
      // En mode hotspot, on considère toujours la connexion comme possible
      // La vraie vérification se fera lors de la tentative de connexion
      if (mode == ConnectionMode.hotspot) {
        return (isConnected: true, mode: mode);
      }
      
      // En mode WiFi, on vérifie la connectivité réelle
      if (mode == ConnectionMode.wifi) {
        final connectivity = await _connectivityService.getCurrentConnection();
        final hasWifi = connectivity.contains(ConnectivityResult.wifi);
        return (isConnected: hasWifi, mode: mode);
      }
      
      return (isConnected: false, mode: ConnectionMode.unknown);
    } catch (e) {
      print('❌ Erreur vérification connectivité: $e');
      // En cas d'erreur, on permet la tentative de connexion
      return (isConnected: true, mode: ConnectionMode.unknown);
    }
  }

  /// Définit le type de microcontrôleur manuellement
  void setMicrocontrollerType(MicrocontrollerType type) {
    _microcontrollerType = type;
    print('WiFiControlManager: Type microcontrôleur défini sur: $type');
  }

  /// Connexion HTTP simple sans envoyer de commande - VERSION SIMPLIFIÉE
  Future<ConnectionResult> connectHttp(String ip, {int port = 80}) async {
    // 1. Validation des paramètres
    final validation = _validateConnectionParams(ip, port);
    if (!validation.isValid) {
      return (
        success: false,
        message: 'Échec de connexion: ${validation.errorMessage!}',
        errorType: ConnectionErrorType.invalidIpOrPort,
        connectionMode: ConnectionMode.unknown
      );
    }

    // 2. Test de connexion direct (plus simple)
    try {
      final testResult = await _httpService.testConnection(ip: ip, port: port);
      
      if (testResult.success) {
        // Mise à jour de l'état seulement si le test réussit
        setActiveProtocol(WiFiProtocol.http);
        _currentIpAddress = ip;
        _currentPort = port;
        
        // Déterminer le mode après connexion réussie
        final connectivity = await checkWifiConnectivity();
        _currentConnectionMode = connectivity.mode;
        
        _lastSuccessfulCommandTime = DateTime.now();

        return (
          success: true,
          message: 'Connexion HTTP réussie',
          errorType: ConnectionErrorType.none,
          connectionMode: connectivity.mode
        );
      } else {
        return (
          success: false,
          message: 'Échec de la connexion HTTP: ${testResult.message}',
          errorType: ConnectionErrorType.connectionFailed,
          connectionMode: ConnectionMode.unknown
        );
      }
    } catch (e) {
      final errorAnalysis = _analyzeConnectionError(e.toString());
      return (
        success: false,
        message: 'Erreur de connexion: ${errorAnalysis.message}',
        errorType: errorAnalysis.errorType,
        connectionMode: ConnectionMode.unknown
      );
    }
  }

  /// Connexion WebSocket avec gestion détaillée des erreurs - VERSION SIMPLIFIÉE
  Future<ConnectionResult> connectWebSocket(String ip, {int port = 81}) async {
    // 1. Validation des paramètres
    final validation = _validateConnectionParams(ip, port);
    if (!validation.isValid) {
      return (
        success: false,
        message: 'Échec de connexion: ${validation.errorMessage!}',
        errorType: ConnectionErrorType.invalidIpOrPort,
        connectionMode: ConnectionMode.unknown
      );
    }

    // 2. Mise à jour de l'état et connexion
    setActiveProtocol(WiFiProtocol.websocket);
    _webSocketService.setWebSocketPort(port);
    _currentIpAddress = ip;
    _currentPort = port;

    // Annuler les tentatives de reconnexion précédentes
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _currentRetries = 0;

    try {
      final bool connected = await _webSocketService.connect(ip);
      
      if (connected) {
        // Déterminer le mode après connexion réussie
        final connectivity = await checkWifiConnectivity();
        _currentConnectionMode = connectivity.mode;
        
        _lastSuccessfulCommandTime = DateTime.now();
        return (
          success: true,
          message: 'Connexion WebSocket réussie',
          errorType: ConnectionErrorType.none,
          connectionMode: connectivity.mode
        );
      } else {
        return (
          success: false,
          message: 'Échec de la connexion WebSocket. Vérifiez l\'IP, le port et l\'état du device.',
          errorType: ConnectionErrorType.connectionFailed,
          connectionMode: ConnectionMode.unknown
        );
      }
    } catch (e) {
      final errorDetails = _analyzeConnectionError(e.toString());
      return (
        success: false,
        message: 'Erreur WebSocket: ${errorDetails.message}',
        errorType: errorDetails.errorType,
        connectionMode: ConnectionMode.unknown
      );
    }
  }

  /// Envoi de commande HTTP avec détection automatique du type
  Future<ConnectionResult> sendHttpCommand({
    required String ip,
    required int port,
    required String command,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // 1. Validation des paramètres
    final validation = _validateConnectionParams(ip, port);
    if (!validation.isValid) {
      return (
        success: false,
        message: 'Échec de la commande: ${validation.errorMessage!}',
        errorType: ConnectionErrorType.invalidIpOrPort,
        connectionMode: ConnectionMode.unknown
      );
    }

    // 2. Mise à jour de l'état
    setActiveProtocol(WiFiProtocol.http);
    _currentIpAddress = ip;
    _currentPort = port;

    // 3. Envoi de la commande avec détection automatique
    try {
      final response = await _sendAdaptiveHttpCommand(ip, port, command, timeout);

      if (!response.success) {
        final errorAnalysis = _analyzeConnectionError(response.message);
        return (
          success: false,
          message: 'Échec de la commande HTTP: ${response.message}',
          errorType: errorAnalysis.errorType,
          connectionMode: ConnectionMode.unknown
        );
      }

      // Déterminer le mode après commande réussie
      final connectivity = await checkWifiConnectivity();
      _currentConnectionMode = connectivity.mode;
      
      // Mettre à jour le timestamp de la dernière commande réussie
      _lastSuccessfulCommandTime = DateTime.now();

      return (
        success: true,
        message: response.message,
        errorType: ConnectionErrorType.none,
        connectionMode: connectivity.mode
      );
    } catch (e) {
      final errorAnalysis = _analyzeConnectionError(e.toString());
      return (
        success: false,
        message: 'Erreur inattendue HTTP: ${e.toString()}',
        errorType: errorAnalysis.errorType,
        connectionMode: ConnectionMode.unknown
      );
    }
  }

  /// Envoi de message WebSocket
  Future<ConnectionResult> sendWebSocketCommand(String message) async {
    if (_activeProtocol != WiFiProtocol.websocket) {
      return (
        success: false,
        message: 'Le protocole WebSocket n\'est pas actif',
        errorType: ConnectionErrorType.protocolError,
        connectionMode: _currentConnectionMode
      );
    }

    if (!_webSocketService.currentIsConnected) {
      return (
        success: false,
        message: 'WebSocket déconnecté',
        errorType: ConnectionErrorType.connectionFailed,
        connectionMode: _currentConnectionMode
      );
    }

    try {
      _webSocketService.sendMessage(message);
      _lastSuccessfulCommandTime = DateTime.now();
      
      return (
        success: true,
        message: 'Message WebSocket envoyé',
        errorType: ConnectionErrorType.none,
        connectionMode: _currentConnectionMode
      );
    } catch (e) {
      return (
        success: false,
        message: 'Erreur lors de l\'envoi WebSocket: ${e.toString()}',
        errorType: ConnectionErrorType.connectionFailed,
        connectionMode: _currentConnectionMode
      );
    }
  }

  /// Méthode adaptative pour envoyer des commandes HTTP avec détection automatique
  Future<({bool success, String message})> _sendAdaptiveHttpCommand(
      String ip, int port, String command, Duration timeout) async {
    
    // Clé de cache pour cette IP
    final cacheKey = '$ip:$port';
    
    // Détection automatique si nécessaire
    if (_microcontrollerType == MicrocontrollerType.auto && !_typeCache.containsKey(cacheKey)) {
      await _detectMicrocontrollerType(ip, port, timeout);
    }

    final effectiveType = _typeCache[cacheKey] ?? _microcontrollerType;

    switch (effectiveType) {
      case MicrocontrollerType.direct:
        return await _sendDirectCommand(ip, port, command, timeout);
      
      case MicrocontrollerType.parameter:
        return await _sendParameterCommand(ip, port, command, timeout);
      
      case MicrocontrollerType.auto:
      case MicrocontrollerType.unknown:
      default:
        // Essai séquentiel des deux formats
        return await _tryBothCommandFormats(ip, port, command, timeout);
    }
  }

  /// Détection automatique du type de microcontrôleur
  Future<void> _detectMicrocontrollerType(String ip, int port, Duration timeout) async {
    final cacheKey = '$ip:$port';
    
    print('🔍 Détection du type de microcontrôleur pour $ip:$port...');

    // Test avec une commande simple
    const testCommand = 'status';
    
    final directResult = await _sendDirectCommand(ip, port, testCommand, timeout);
    final paramResult = await _sendParameterCommand(ip, port, testCommand, timeout);

    // Analyse des résultats
    if (directResult.success && !paramResult.success) {
      _typeCache[cacheKey] = MicrocontrollerType.direct;
      print('✅ Type détecté: DIRECT (WiFi.h + WiFiServer)');
    } else if (paramResult.success && !directResult.success) {
      _typeCache[cacheKey] = MicrocontrollerType.parameter;
      print('✅ Type détecté: PARAMÉTRÉ (WebServer.h)');
    } else if (directResult.success && paramResult.success) {
      // Les deux fonctionnent, priorité au direct (plus courant)
      _typeCache[cacheKey] = MicrocontrollerType.direct;
      print('✅ Type détecté: LES DEUX (priorité DIRECT)');
    } else {
      _typeCache[cacheKey] = MicrocontrollerType.unknown;
      print('❌ Type détecté: INCONNU (aucun format ne fonctionne)');
    }
  }

  /// Essai séquentiel des deux formats
  Future<({bool success, String message})> _tryBothCommandFormats(
      String ip, int port, String command, Duration timeout) async {
    
    print('🔄 Essai des deux formats de commande...');
    
    // Essai format direct d'abord
    final directResult = await _sendDirectCommand(ip, port, command, timeout);
    if (_isSuccessfulResponse(directResult)) {
      _typeCache['$ip:$port'] = MicrocontrollerType.direct;
      return directResult;
    }

    // Essai format paramétré
    final paramResult = await _sendParameterCommand(ip, port, command, timeout);
    if (_isSuccessfulResponse(paramResult)) {
      _typeCache['$ip:$port'] = MicrocontrollerType.parameter;
      return paramResult;
    }

    // Les deux ont échoué, retourner le résultat le plus prometteur
    return directResult.message.contains('404') ? paramResult : directResult;
  }

  /// Vérifie si une réponse est considérée comme réussie
  bool _isSuccessfulResponse(({bool success, String message}) response) {
    return response.success || 
           response.message.contains('200') ||
           response.message.contains('OK') ||
           (response.message.contains('ESP32') && !response.message.contains('404'));
  }

  /// Envoi en format direct (WiFi.h + WiFiServer)
  Future<({bool success, String message})> _sendDirectCommand(
      String ip, int port, String command, Duration timeout) async {
    try {
      final url = Uri.parse('http://$ip:$port/$command');
      final response = await http.get(url).timeout(timeout);
      
      return (
        success: response.statusCode == 200,
        message: 'HTTP ${response.statusCode}: ${response.body}'
      );
    } catch (e) {
      return (success: false, message: 'Format direct échoué: $e');
    }
  }

  /// Envoi en format paramétré (WebServer.h)
  Future<({bool success, String message})> _sendParameterCommand(
      String ip, int port, String command, Duration timeout) async {
    try {
      final url = Uri.parse('http://$ip:$port/cmd?c=${Uri.encodeComponent(command)}');
      final response = await http.get(url).timeout(timeout);
      
      return (
        success: response.statusCode == 200,
        message: 'HTTP ${response.statusCode}: ${response.body}'
      );
    } catch (e) {
      return (success: false, message: 'Format paramétré échoué: $e');
    }
  }

  /// Analyse des erreurs de connexion
  ({String message, ConnectionErrorType errorType}) _analyzeConnectionError(String error) {
    final errorString = error.toLowerCase();

    if (errorString.contains('timeout')) {
      return (message: 'Timeout de connexion', errorType: ConnectionErrorType.timeout);
    } else if (errorString.contains('dns') || errorString.contains('hostlookup')) {
      return (message: 'Impossible de résoudre l\'adresse', errorType: ConnectionErrorType.dnsLookupFailed);
    } else if (errorString.contains('connection refused') || errorString.contains('refused')) {
      return (message: 'Connexion refusée par le device', errorType: ConnectionErrorType.connectionFailed);
    } else if (errorString.contains('handshake') || errorString.contains('websocket')) {
      return (message: 'Erreur de protocole WebSocket', errorType: ConnectionErrorType.protocolError);
    } else if (errorString.contains('401')) {
      return (message: 'Non autorisé', errorType: ConnectionErrorType.unauthorized);
    } else if (errorString.contains('403')) {
      return (message: 'Accès interdit', errorType: ConnectionErrorType.forbidden);
    } else if (errorString.contains('404')) {
      return (message: 'Ressource non trouvée', errorType: ConnectionErrorType.notFound);
    } else if (errorString.contains('50')) {
      return (message: 'Erreur serveur', errorType: ConnectionErrorType.serverError);
    }

    return (message: 'Erreur de connexion: $error', errorType: ConnectionErrorType.unknown);
  }

  String _getConnectivityErrorMessage(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.hotspot:
        return 'Le mode hotspot n\'est pas actif';
      case ConnectionMode.wifi:
        return 'Le Wi-Fi n\'est pas connecté';
      case ConnectionMode.unknown:
        return 'Aucune connexion réseau détectée';
    }
  }

  String _getModeName(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.wifi:
        return 'Wi-Fi';
      case ConnectionMode.hotspot:
        return 'Hotspot';
      case ConnectionMode.unknown:
        return 'Inconnu';
    }
  }

  // Méthodes utilitaires
  Future<bool> isWifiConnected() async {
    return await _connectivityService.isWifiConnected();
  }

  Future<List<ConnectivityResult>> getCurrentConnection() async {
    return await _connectivityService.getCurrentConnection();
  }

  Future<String?> getLocalWifiIp() async {
    try {
      return await _networkInfoService.getLocalIp();
    } catch (e) {
      print('Erreur lors de la récupération de l\'IP locale: $e');
      return null;
    }
  }

  Future<String?> getWifiGatewayIp() async {
    try {
      return await _networkInfoService.getGateway();
    } catch (e) {
      print('Erreur lors de la récupération de la passerelle: $e');
      return null;
    }
  }

  void setActiveProtocol(WiFiProtocol protocol) {
    if (_activeProtocol != protocol) {
      disconnectAllConnections();
    }
    _activeProtocol = protocol;
    print('WiFiControlManager: Protocole actif défini sur: $_activeProtocol.');
  }

  WiFiProtocol getActiveProtocol() => _activeProtocol;

  void startHttpPolling({
    required String ip,
    required int port,
    required String command,
    required Duration interval,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final validation = _validateConnectionParams(ip, port);
    if (!validation.isValid) {
      print('WiFiControlManager: Échec du démarrage du polling: ${validation.errorMessage!}');
      return;
    }

    final connectivity = await checkWifiConnectivity();
    if (!connectivity.isConnected) {
      print('WiFiControlManager: Impossible de démarrer le polling, connexion absente.');
      return;
    }

    setActiveProtocol(WiFiProtocol.http);
    _currentIpAddress = ip;
    _currentPort = port;
    _currentConnectionMode = connectivity.mode;

    _httpService.startPolling(
      ip: ip,
      port: port,
      command: command,
      interval: interval,
      timeout: timeout,
    );
  }

  void stopPolling() {
    _httpService.stopPolling();
  }

  void sendWebSocketMessage(String message) {
    if (_activeProtocol == WiFiProtocol.websocket && _webSocketService.currentIsConnected) {
      _webSocketService.sendMessage(message);
      _lastSuccessfulCommandTime = DateTime.now();
    } else if (_activeProtocol != WiFiProtocol.websocket) {
      print('WiFiControlManager: Le protocole WebSocket n\'est pas le protocole actif.');
    } else {
      print('WiFiControlManager: WebSocket non connecté. Message non envoyé.');
    }
  }

  void disconnectWebSocket() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _webSocketService.disconnect();
  }

  void disconnectAllConnections() {
    print('WiFiControlManager: Déconnexion de toutes les connexions actives.');
    _httpService.stopPolling();
    _webSocketService.disconnect();
    _activeProtocol = WiFiProtocol.none;
    _currentIpAddress = null;
    _currentPort = null;
    _currentConnectionMode = ConnectionMode.unknown;
    _lastSuccessfulCommandTime = null;
    _typeCache.clear(); // Vider le cache à la déconnexion
  }

  void _attemptWebSocketReconnect() {
    if (_reconnectTimer != null || _currentIpAddress == null) return;

    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_currentRetries >= _maxRetries) {
        print('Échec de la reconnexion WebSocket après $_maxRetries tentatives.');
        disconnectWebSocket();
        timer.cancel();
        _reconnectTimer = null;
        return;
      }

      print('Tentative de reconnexion WebSocket: ${_currentRetries + 1}/$_maxRetries');
      final result = await connectWebSocket(_currentIpAddress!);
      
      if (result.success) {
        print('Reconnexion WebSocket réussie.');
        timer.cancel();
        _reconnectTimer = null;
        _currentRetries = 0;
      } else {
        _currentRetries++;
      }
    });
  }

  ({bool isValid, String? errorMessage}) _validateConnectionParams(String ip, int port) {
    if (ip.isEmpty || !_isValidIp(ip)) {
      return (isValid: false, errorMessage: 'Adresse IP non valide.');
    }
    if (port <= 0 || port > 65535) {
      return (isValid: false, errorMessage: 'Port non valide (doit être entre 1 et 65535).');
    }
    return (isValid: true, errorMessage: null);
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (var part in parts) {
      final int? value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }

  void dispose() {
    disconnectAllConnections();
    _reconnectTimer?.cancel();
    _httpService.dispose();
    _webSocketService.dispose();
  }
}