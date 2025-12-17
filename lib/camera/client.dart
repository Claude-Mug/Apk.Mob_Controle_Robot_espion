// client.dart - Version corrigée avec gestion robuste des connexions
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

class CameraClient {
  String _serverIP = '';
  int _serverPort = 8080;
  bool _isConnected = false;
  bool _isRecording = false;
  bool _isStreaming = false;
  String _connectionStatus = "Non connecté";
  Timer? _statusTimer;
  bool _flashEnabled = false;
  String _currentLocation = "Non disponible";
  bool _gpsEnabled = false;

  // Streams pour les mises à jour d'état
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _messageController = StreamController<String>.broadcast();

   // NOUVELLES VARIABLES POUR LE STREAMING
  final List<int> _streamBuffer = [];
  StreamSubscription<List<int>>? _streamSubscription;  // List<int> pas Uint8List
  final StreamController<Uint8List> _videoStreamController = 
      StreamController<Uint8List>.broadcast();
  
  Stream<Uint8List>? get videoStream => _videoStreamController.stream;
  

  // Getters
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;

  bool get isConnected => _isConnected;
  bool get isRecording => _isRecording;
  bool get isStreaming => _isStreaming;
  String get connectionStatus => _connectionStatus;
  String get serverIP => _serverIP;
  int get serverPort => _serverPort;
  bool get flashEnabled => _flashEnabled;
  String get currentLocation => _currentLocation;
  bool get gpsEnabled => _gpsEnabled;

  // Configuration du serveur
  void setServer(String ip, int port) {
    _serverIP = ip;
    _serverPort = port;
    _addMessage("Serveur configuré: $ip:$port");
  }

  // Méthode de connexion améliorée avec gestion d'erreurs détaillée
  // Remplacer connectToServerWithRetry par cette version améliorée
Future<Map<String, dynamic>> connectToServerWithRetry({
  int maxRetries = 3,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (_serverIP.isEmpty) {
    return {
      'success': false, 
      'error': 'Adresse IP non spécifiée',
      'details': 'Veuillez entrer une adresse IP valide'
    };
  }

  // Test de connectivité réseau d'abord
  _addMessage('🔍 Test de connectivité réseau...');
  final connectivityTest = await testNetworkConnectivity(_serverIP, _serverPort);
  if (!connectivityTest['success']) {
    return {
      'success': false,
      'error': 'Problème de connectivité réseau',
      'details': 'Impossible d\'atteindre l\'adresse $serverIP',
      'connectivity_test': connectivityTest
    };
  }

  Map<String, dynamic>? lastError;
  
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    _updateConnectionStatus("Tentative de connexion $attempt/$maxRetries...");
    _addMessage('🔗 Tentative $attempt: Connexion à $_serverIP:$_serverPort');

    try {
      final result = await _attemptConnection(timeout);
      
      if (result['success']) {
        return {
          'success': true,
          'message': 'Connexion réussie',
          'server': '$_serverIP:$_serverPort',
          'attempt': attempt
        };
      } else {
        lastError = result;
        _addMessage('❌ Tentative $attempt échouée: ${result['error']}');
        
        // Essayer les ports alternatifs seulement si l'erreur est de type connexion
        if (attempt == 1 && result['type'] == 'SocketException') {
          final portResult = await _tryAlternativePortsDetailed();
          if (portResult['success']) {
            return portResult;
          }
        }
      }
    } catch (e) {
      lastError = {
        'success': false,
        'error': 'Erreur inattendue',
        'details': e.toString(),
        'attempt': attempt
      };
      _addMessage('❌ Erreur tentative $attempt: $e');
    }

    // Attendre avant la prochaine tentative (backoff exponentiel)
    if (attempt < maxRetries) {
      final delay = Duration(seconds: attempt * 2);
      _addMessage('⏳ Nouvelle tentative dans ${delay.inSeconds}s...');
      await Future.delayed(delay);
    }
  }

  // Si toutes les tentatives ont échoué
  return lastError ?? {
    'success': false,
    'error': 'Échec de connexion après $maxRetries tentatives',
    'details': 'Vérifiez que:\n• Le serveur est démarré\n• L\'adresse IP est correcte\n• Le port est ouvert\n• Les appareils sont sur le même réseau WiFi'
  };
}

  // CORRECTION : Méthode de connexion avec gestion robuste de l'encodage
  // CORRECTION : Méthode de connexion avec gestion robuste de l'encodage
Future<Map<String, dynamic>> _attemptConnection(Duration timeout) async {
  try {
    final response = await http.get(
      Uri.parse('http://$_serverIP:$_serverPort/status'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'User-Agent': 'CameraClient/1.0',
      },
    ).timeout(timeout);

    if (response.statusCode == 200) {
      try {
        // SOLUTION 1 : Décodage avec gestion d'erreurs UTF-8
        String responseBody;
        try {
          responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
        } catch (e) {
          // Si le décodage UTF-8 échoue, essayer Latin1
          _addMessage('⚠️ Erreur UTF-8, tentative Latin1...');
          responseBody = latin1.decode(response.bodyBytes);
        }
        
        // Nettoyer la réponse (supprimer caractères invisibles)
        responseBody = responseBody.trim();
        
        // Vérifier si le corps de la réponse est vide
        if (responseBody.isEmpty) {
          return {
            'success': false,
            'error': 'Réponse vide du serveur',
            'details': 'Le serveur a répondu avec un corps vide',
            'type': 'EmptyResponse'
          };
        }

        // Tentative de parsing JSON avec gestion d'erreur spécifique
        dynamic data;
        try {
          data = json.decode(responseBody) as Map<String, dynamic>;
        } catch (jsonError) {
          // Si le JSON est invalide, afficher un aperçu pour diagnostic
          _addMessage('❌ JSON invalide: ${responseBody.substring(0, min(100, responseBody.length))}');
          return {
            'success': false,
            'error': 'Format de réponse invalide',
            'details': 'Erreur JSON: $jsonError\nRéponse (${responseBody.length} chars): ${responseBody.substring(0, min(200, responseBody.length))}...',
            'type': 'JsonDecodeError',
            'raw_response': responseBody.substring(0, min(500, responseBody.length))
          };
        }
        
        // Vérifier que c'est bien un serveur de caméra
        final bool isCameraServer = 
            (data['camera_ready'] != null) ||
            (data['streaming'] != null) ||
            (data['recording'] != null) ||
            (data['server_version'] != null) ||
            (data['device_name'] != null) ||
            (data['status'] != null && data['status'] is String && data['status'].toLowerCase().contains('camera'));

        if (isCameraServer) {
          _handleSuccessfulConnection();
          return {'success': true};
        } else {
          return {
            'success': false,
            'error': 'Serveur trouvé mais pas un serveur de caméra',
            'details': 'Réponse: ${responseBody.length > 100 ? responseBody.substring(0, 100) + "..." : responseBody}',
            'type': 'NotCameraServer'
          };
        }
      } catch (e) {
        // Gestion spécifique des erreurs d'encodage/JSON
        return {
          'success': false,
          'error': 'Erreur de traitement de la réponse',
          'details': 'Erreur: $e\nType: ${e.runtimeType}\nStatus: ${response.statusCode}',
          'type': 'ProcessingError'
        };
      }
    } else {
      return {
        'success': false,
        'error': 'Erreur HTTP ${response.statusCode}',
        'details': 'Le serveur a répondu avec un statut d\'erreur',
        'type': 'HttpError'
      };
    }
  } catch (e) {
    return {
      'success': false,
      'error': _getConnectionError(e),
      'details': e.toString(),
      'type': e.runtimeType.toString()
    };
  }
}

  // CORRECTION : Méthode améliorée pour tester les ports alternatifs
  Future<Map<String, dynamic>> _tryAlternativePortsDetailed() async {
    final commonPorts = [8080, 8081, 8082, 8000, 8888, 5000, 3000, 8085, 8086, 80, 443];
    final originalPort = _serverPort;
    
    _addMessage('🔄 Essai des ports alternatifs...');

    for (final port in commonPorts) {
      if (port == originalPort) continue;
      
      try {
        _addMessage('🔍 Test du port $port...');
        final response = await http.get(
          Uri.parse('http://$_serverIP:$port/status'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          try {
            final responseBody = utf8.decode(response.bodyBytes);
            final data = json.decode(responseBody) as Map<String, dynamic>;
            final bool isCameraServer = 
                (data['camera_ready'] != null) ||
                (data['streaming'] != null) ||
                (data['recording'] != null);

            if (isCameraServer) {
              _serverPort = port;
              _handleSuccessfulConnection();
              _addMessage('✅ Serveur trouvé sur le port $port');
              
              return {
                'success': true,
                'message': 'Serveur trouvé sur le port alternatif $port',
                'original_port': originalPort,
                'new_port': port
              };
            }
          } catch (e) {
            // Continuer avec le port suivant si JSON invalide
            continue;
          }
        }
      } catch (e) {
        // Continuer avec le port suivant
        continue;
      }
    }

    return {
      'success': false,
      'error': 'Aucun port alternatif valide trouvé',
      'details': 'Ports testés: ${commonPorts.where((p) => p != originalPort).join(', ')}'
    };
  }

  // Remplacer la méthode _getConnectionError
String _getConnectionError(dynamic error) {
  if (error is SocketException) {
    final osError = error.osError;
    if (osError != null) {
      switch (osError.errorCode) {
        case 111: // Connection refused
          return 'Connexion refusée - Le serveur n\'est pas démarré ou le port est incorrect';
        case 110: // Connection timeout
          return 'Timeout de connexion - Le serveur ne répond pas';
        case 113: // No route to host
          return 'Aucune route vers l\'hôte - Vérifiez l\'adresse IP';
        case 101: // Network unreachable
          return 'Réseau inaccessible - Vérifiez la connexion WiFi';
        default:
          return 'Erreur socket (${osError.errorCode}): ${osError.message}';
      }
    }
    return 'Impossible de se connecter au serveur';
  } else if (error is TimeoutException) {
    return 'Timeout - Le serveur ne répond pas dans le délai imparti';
  } else if (error is HttpException) {
    return 'Erreur HTTP lors de la connexion';
  } else if (error is HandshakeException) {
    return 'Erreur de handshake SSL';
  } else if (error is FormatException) {
    return 'Erreur de format de données';
  } else {
    return 'Erreur de connexion: ${error.toString()}';
  }
}

 bool _isValidJpegBytes(Uint8List bytes) {
  if (bytes.length < 4) return false;
  
  // Vérifier les markers JPEG
  // Start: 0xFF 0xD8
  // End: 0xFF 0xD9
  final hasValidStart = bytes[0] == 0xFF && bytes[1] == 0xD8;
  final hasValidEnd = bytes[bytes.length - 2] == 0xFF && 
                      bytes[bytes.length - 1] == 0xD9;
  
  return hasValidStart && hasValidEnd;
}

// Nouvelle méthode pour lire le flux MJPEG
 Future<void> startVideoStream() async {
  if (!_isConnected) {
    _addMessage('❌ Non connecté au serveur');
    return;
  }

  try {
    _addMessage('🔴 Démarrage du flux vidéo MJPEG...');
    
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    
    final request = await client.getUrl(
      Uri.parse('http://$_serverIP:$_serverPort/stream')
    );
    
    // Headers importants pour le streaming
    request.headers.set('Accept', 'multipart/x-mixed-replace');
    request.headers.set('Connection', 'keep-alive');
    
    final response = await request.close();
    
    if (response.statusCode == 200) {
      _addMessage('✅ Connexion au flux établie');
      
      // Vider le buffer au démarrage
      _streamBuffer.clear();
      
      // CORRECTION: response.listen retourne Stream<List<int>> pas Stream<Uint8List>
      _streamSubscription = response.listen(
        _onStreamData,  // Cette méthode accepte maintenant List<int>
        onError: (error) {
          _addMessage('❌ Erreur flux: $error');
          stopVideoStream();
        },
        onDone: () {
          _addMessage('🟢 Flux vidéo terminé');
          stopVideoStream();
        },
        cancelOnError: false,
      );
      
    } else {
      _addMessage('❌ Erreur HTTP ${response.statusCode}');
    }
  } catch (e) {
    _addMessage('❌ Erreur démarrage flux: $e');
  }
}

 void _onStreamData(List<int> chunk) {
  _streamBuffer.addAll(chunk);
  
  // 1. Attendre d'avoir assez de données (>1KB)
  if (_streamBuffer.length < 1024) return;
  
  // 2. Chercher une image complète
  final startIndex = _findJpegStart(_streamBuffer);
  final endIndex = _findJpegEnd(_streamBuffer, startIndex + 2);
  
  // 3. Si pas d'image complète, ATTENDRE
  if (endIndex == -1) return;
  
  // 4. Vérifier la taille (entre 1KB et 5MB)
  final imageSize = endIndex - startIndex + 2;
  if (imageSize < 1024 || imageSize > 5 * 1024 * 1024) {
    // Ignorer les images invalides
    _streamBuffer.removeRange(0, endIndex + 2);
    return;
  }
  
  // 5. Extraire et valider l'image
  final imageData = Uint8List.fromList(
    _streamBuffer.sublist(startIndex, endIndex + 2)
  );
  
  if (_isValidJpegBytes(imageData)) {
    _videoStreamController.add(imageData); // OK !
  }
}


  int _findJpegStart(List<int> buffer) {
  for (int i = 0; i < buffer.length - 1; i++) {
    if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
      return i;
    }
  }
  return -1;
}

int _findJpegEnd(List<int> buffer, int startFrom) {
  for (int i = startFrom; i < buffer.length - 1; i++) {
    if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
      return i;
    }
  }
  return -1;
}

 Future<void> stopVideoStream() async {
  try {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamBuffer.clear();
    _addMessage('🟢 Flux vidéo arrêté');
  } catch (e) {
    _addMessage('⚠️ Erreur arrêt flux: $e');
  }
}

  // Connexion avec gestion améliorée des hotspots
  Future<bool> connectToServer() async {
    if (_serverIP.isEmpty) {
      _updateConnectionStatus("Veuillez entrer une adresse IP");
      return false;
    }

    _updateConnectionStatus("Connexion en cours...");

    try {
      // Utiliser la nouvelle méthode robuste
      final result = await connectToServerWithRetry(maxRetries: 1, timeout: const Duration(seconds: 5));
      
      if (result['success']) {
        return true;
      } else {
        _updateConnectionStatus("Échec de connexion");
        _addMessage('Échec connexion: ${result['error']}');
        return false;
      }
    } catch (e) {
      _addMessage('Erreur connexion: ${e.toString()}');
      return false;
    }
  }

  void _handleSuccessfulConnection() {
    _isConnected = true;
    _updateConnectionStatus("Connecté au serveur");
    _startStatusUpdates();
    _addMessage('Connexion réussie au serveur $_serverIP:$_serverPort');
    _notifyStatusUpdate();
  }

  // CORRECTION : Méthode de mise à jour du statut avec gestion d'erreur améliorée
  void _startStatusUpdates() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isConnected) {
        timer.cancel();
        return;
      }

      try {
        final response = await http.get(
          Uri.parse('http://$_serverIP:$_serverPort/status'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          try {
            final responseBody = utf8.decode(response.bodyBytes);
            final data = json.decode(responseBody) as Map<String, dynamic>;
            _isRecording = data['recording'] ?? false;
            _isStreaming = data['streaming'] ?? false;
            _notifyStatusUpdate();
          } catch (e) {
            _addMessage('❌ Erreur parsing statut: $e');
          }
        } else {
          throw Exception('Statut HTTP ${response.statusCode}');
        }
      } catch (e) {
        _isConnected = false;
        _updateConnectionStatus("Connexion perdue");
        _isRecording = false;
        _isStreaming = false;
        timer.cancel();
        _addMessage('Connexion au serveur perdue: ${e.toString()}');
      }
    });
  }

  // Ajouter cette méthode dans CameraClient
Future<Map<String, dynamic>> testNetworkConnectivity(String ip, int port) async {
  try {
    _addMessage('🔍 Test de connectivité vers $ip:$port');
    
    // Test de ping (utilisation de socket raw)
    final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
    await socket.close();
    
    return {
      'success': true,
      'message': 'Connectivité réseau OK',
      'ip': ip,
      'port': port
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Erreur de connectivité',
      'details': e.toString(),
      'type': e.runtimeType.toString()
    };
  }
}

  // === MÉTHODES CAMÉRA AMÉLIORÉES ===

  // CORRECTION : Méthodes avec gestion robuste des réponses
  Future<Map<String, dynamic>> _makeApiRequest(String endpoint, {Map<String, dynamic>? body, String method = 'POST'}) async {
    if (!_isConnected) {
      return {'success': false, 'error': 'Non connecté au serveur'};
    }

    try {
      final uri = Uri.parse('http://$_serverIP:$_serverPort$endpoint');
      http.Response response;

      if (method == 'POST' && body != null) {
        response = await http.post(
          uri,
          body: json.encode(body),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ).timeout(const Duration(seconds: 10));
      } else if (method == 'POST') {
        response = await http.post(uri).timeout(const Duration(seconds: 10));
      } else {
        response = await http.get(uri).timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        try {
          final responseBody = utf8.decode(response.bodyBytes);
          final data = json.decode(responseBody) as Map<String, dynamic>;
          return {'success': true, ...data};
        } catch (e) {
          return {
            'success': false, 
            'error': 'Réponse invalide du serveur',
            'details': 'Erreur JSON: $e'
          };
        }
      } else {
        return {
          'success': false,
          'error': 'Erreur serveur: ${response.statusCode}',
          'details': 'Réponse: ${response.body.length > 100 ? response.body.substring(0, 100) + "..." : response.body}'
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> capturePhoto() async {
    final result = await _makeApiRequest('/capture');
    if (result['success']) {
      _addMessage('Photo capturée: ${result['file_path']}');
    }
    return result;
  }

  Future<Map<String, dynamic>> startRecording() async {
    final result = await _makeApiRequest('/record/start');
    if (result['success']) {
      _isRecording = true;
      _addMessage('Enregistrement démarré');
      _notifyStatusUpdate();
    }
    return result;
  }

  Future<Map<String, dynamic>> stopRecording() async {
    final result = await _makeApiRequest('/record/stop');
    if (result['success']) {
      _isRecording = false;
      _addMessage('Enregistrement arrêté: ${result['file_path']}');
      _notifyStatusUpdate();
    }
    return result;
  }

  Future<Map<String, dynamic>> toggleRecording() async {
    if (_isRecording) {
      return await stopRecording();
    } else {
      return await startRecording();
    }
  }

  Future<Map<String, dynamic>> startStreaming() async {
    final result = await _makeApiRequest('/stream/start');
    if (result['success']) {
      _isStreaming = true;
      _addMessage('Streaming démarré');
      _notifyStatusUpdate();
    }
    return result;
  }

  Future<Map<String, dynamic>> stopStreaming() async {
    final result = await _makeApiRequest('/stream/stop');
    if (result['success']) {
      _isStreaming = false;
      _addMessage('Streaming arrêté');
      _notifyStatusUpdate();
    }
    return result;
  }

  Future<Map<String, dynamic>> toggleStreaming() async {
    if (_isStreaming) {
      return await stopStreaming();
    } else {
      return await startStreaming();
    }
  }

  Future<Map<String, dynamic>> switchCamera() async {
    final result = await _makeApiRequest('/switch-camera');
    if (result['success']) {
      _addMessage('Caméra changée: ${result['camera']}');
    }
    return result;
  }

  // === NOUVELLES MÉTHODES POUR FLASH, GPS, TIMER ===

  Future<Map<String, dynamic>> toggleFlash() async {
    final result = await _makeApiRequest('/flash');
    if (result['success']) {
      _flashEnabled = result['flash_enabled'] ?? false;
      _addMessage('Flash ${_flashEnabled ? 'activé' : 'désactivé'}');
    }
    return {
      'success': result['success'],
      'flash_mode': _flashEnabled ? 'on' : 'off',
      'error': result['error']
    };
  }

  Future<Map<String, dynamic>> setTimer(int seconds) async {
    final result = await _makeApiRequest('/timer', body: {'seconds': seconds});
    if (result['success']) {
      _addMessage('Minuterie réglée sur $seconds secondes');
    }
    return result;
  }

  Future<Map<String, dynamic>> startGPS() async {
    final result = await _makeApiRequest('/gps/start');
    if (result['success']) {
      _gpsEnabled = true;
      _currentLocation = result['location'] ?? "Localisation obtenue";
      _addMessage('GPS activé: $_currentLocation');
    }
    return {
      'success': result['success'],
      'location': _currentLocation,
      'error': result['error']
    };
  }

  Future<Map<String, dynamic>> stopGPS() async {
    final result = await _makeApiRequest('/gps/stop');
    if (result['success']) {
      _gpsEnabled = false;
      _currentLocation = "Non disponible";
      _addMessage('GPS désactivé');
    }
    return result;
  }

  Future<Map<String, dynamic>> getCurrentLocation() async {
    if (!_gpsEnabled) {
      return {'success': false, 'error': 'GPS non activé'};
    }

    final result = await _makeApiRequest('/gps/location', method: 'GET');
    if (result['success']) {
      _currentLocation = result['location'] ?? "Localisation inconnue";
    }
    return {
      'success': result['success'],
      'location': _currentLocation,
      'error': result['error']
    };
  }

  Future<Map<String, dynamic>> shareLocation(String location) async {
  try {
    final response = await http.post(
      Uri.parse('http://$serverIP:$serverPort/gps/share'),
      body: json.encode({'location': location}),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return {
        'success': true,
        'message': data['status'],
        'google_maps_url': data['google_maps_url'] // Nouveau champ
      };
    } else {
      return {
        'success': false,
        'error': 'Erreur serveur: ${response.statusCode}'
      };
    }
  } catch (e) {
    return {
      'success': false,
      'error': 'Erreur partage: $e'
    };
  }
}

  // NOUVELLE MÉTHODE : Test de diagnostic du serveur
  Future<Map<String, dynamic>> diagnoseServer() async {
    _addMessage('🔧 Début du diagnostic serveur...');
    
    final endpoints = [
      '/status', '/', '/api/status', '/camera/status', 
      '/info', '/version', '/health'
    ];

    final results = <String, dynamic>{};

    for (final endpoint in endpoints) {
      try {
        _addMessage('🔍 Test endpoint: $endpoint');
        final response = await http.get(
          Uri.parse('http://$_serverIP:$_serverPort$endpoint'),
          headers: {'Accept': '*/*'},
        ).timeout(const Duration(seconds: 3));

        results[endpoint] = {
          'status_code': response.statusCode,
          'content_type': response.headers['content-type'] ?? 'inconnu',
          'content_length': response.body.length,
          'body_preview': response.body.length > 100 
              ? response.body.substring(0, 100) + '...' 
              : response.body,
        };

        _addMessage('✅ $endpoint: ${response.statusCode} - ${response.headers['content-type']}');
      } catch (e) {
        results[endpoint] = {'error': e.toString()};
        _addMessage('❌ $endpoint: $e');
      }
    }

    return {
      'success': true,
      'diagnostic': results,
      'message': 'Diagnostic terminé'
    };
  }

  // Dans CameraClient (client.dart)
Future<Map<String, dynamic>> testStreamConnection() async {
  try {
    _addMessage('🔍 Test de connexion au flux...');
    
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://$_serverIP:$_serverPort/stream'));
    
    final response = await request.close();
    
    _addMessage('📊 Statut flux: ${response.statusCode}');
    _addMessage('📋 Headers: ${response.headers}');

    if (response.statusCode == 200) {
      // Lire les premières données pour vérifier
      final firstChunk = await response.first;
      _addMessage('📦 Première chunk: ${firstChunk.length} bytes');
      
      return {
        'success': true,
        'status_code': response.statusCode,
        'content_type': response.headers.contentType?.toString(),
        'first_chunk_size': firstChunk.length,
      };
    } else {
      return {
        'success': false,
        'error': 'Statut HTTP ${response.statusCode}',
        'status_code': response.statusCode,
      };
    }
  } catch (e) {
    return {
      'success': false,
      'error': 'Erreur test flux: ${e.toString()}',
      'type': e.runtimeType.toString(),
    };
  }
}

  Future<void> disconnectFromServer() async {
    _statusTimer?.cancel();
    _isConnected = false;
    _isRecording = false;
    _isStreaming = false;
    _updateConnectionStatus("Déconnecté");
    _addMessage('Déconnecté du serveur');
  }

  void _updateConnectionStatus(String status) {
    _connectionStatus = status;
    _connectionController.add(_isConnected);
    _notifyStatusUpdate();
  }

  void _addMessage(String message) {
    _messageController.add(message);
  }

  void _notifyStatusUpdate() {
    final status = {
      'connected': _isConnected,
      'recording': _isRecording,
      'streaming': _isStreaming,
      'connectionStatus': _connectionStatus,
      'serverIP': _serverIP,
      'serverPort': _serverPort,
      'flashEnabled': _flashEnabled,
      'gpsEnabled': _gpsEnabled,
      'currentLocation': _currentLocation,
    };
    _statusController.add(status);
  }

 Future<void> dispose() async {
  await stopVideoStream();
  _statusTimer?.cancel();
  await disconnectFromServer();
  await _connectionController.close();
  await _statusController.close();
  await _messageController.close();
  await _videoStreamController.close();
  
  }
}