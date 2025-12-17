// server.dart - Version corrigée
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';

class CameraServer {
  List<String> get logMessages => List.unmodifiable(_logMessages);
  late int port;
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  HttpServer? _server;
  bool _isStreaming = false;
  bool _isRecording = false;
  String _status = "Serveur arrêté";
  List<String> _connectedClients = [];
  List<String> _logMessages = [];
  int _totalConnections = 0;
  int _photosCaptured = 0;
  int _videosRecorded = 0;
  String _currentResolution = "Moyenne";
  FlashMode _flashMode = FlashMode.off;
  bool _gpsEnabled = false;
  Position? _currentPosition;
  Timer? _gpsTimer;
  int _timerSeconds = 0;
  Timer? _captureTimer;
  
  // Streams pour les mises à jour d'état
  final StreamController<String> _statusController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _statsController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();
  CameraController? get cameraController => _controller;
  bool get isCameraInitialized => _controller?.value.isInitialized ?? false;
  

  CameraServer({this.port = 8080});

  // Getters pour l'accès depuis l'extérieur
  Stream<String> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;
  Stream<String> get logStream => _logController.stream;
  
  bool get isRunning => _server != null;
  bool get isStreaming => _isStreaming;
  bool get isRecording => _isRecording;
  String get currentStatus => _status;
  List<String> get connectedClients => List.unmodifiable(_connectedClients);
  int get totalConnections => _totalConnections;
  int get photosCaptured => _photosCaptured;
  int get videosRecorded => _videosRecorded;

  // AJOUT: Méthode _setCORSHeaders manquante
  void _setCORSHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept');
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
  }

  Future<void> initialize() async {
    try {
      await _initializeCamera();
      await _startServer();
      _addLog("Serveur initialisé sur le port $port");
    } catch (e) {
      _updateStatus("Erreur initialisation: $e");
      _addLog("Erreur initialisation: $e");
      rethrow;
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        throw Exception("Aucune caméra disponible");
      }
      
      _addLog("${_cameras!.length} caméra(s) détectée(s)");
      
      _controller = CameraController(
        _cameras!.first,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      
      await _controller!.initialize();
      _updateStatus("Caméra initialisée - En attente de connexions");
      _addLog("Caméra initialisée: ${_cameras!.first.name}");
    } catch (e) {
      _updateStatus("Erreur caméra: $e");
      _addLog("Erreur initialisation caméra: $e");
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      throw Exception("Une seule caméra disponible");
    }
    
    try {
      final currentIndex = _cameras!.indexOf(_controller!.description);
      final nextIndex = (currentIndex + 1) % _cameras!.length;
      
      await _controller!.dispose();
      
      _controller = CameraController(
        _cameras![nextIndex],
        ResolutionPreset.medium,
        enableAudio: true,
      );
      
      await _controller!.initialize();
      _addLog("Caméra changée vers: ${_cameras![nextIndex].name}");
      _notifyStatsUpdate();
    } catch (e) {
      _addLog("Erreur changement caméra: $e");
      rethrow;
    }
  }

  Future<void> changeResolution(ResolutionPreset resolution) async {
    try {
      final currentCamera = _controller!.description;
      await _controller!.dispose();
      
      _controller = CameraController(
        currentCamera,
        resolution,
        enableAudio: true,
      );
      
      await _controller!.initialize();
      _currentResolution = _getResolutionName(resolution);
      _addLog("Résolution changée: $_currentResolution");
      _notifyStatsUpdate();
    } catch (e) {
      _addLog("Erreur changement résolution: $e");
      rethrow;
    }
  }

  String _getResolutionName(ResolutionPreset resolution) {
    final presets = {
      ResolutionPreset.low: "Basse",
      ResolutionPreset.medium: "Moyenne",
      ResolutionPreset.high: "Haute",
      ResolutionPreset.veryHigh: "Très haute",
      ResolutionPreset.ultraHigh: "Ultra haute",
      ResolutionPreset.max: "Maximale",
    };
    return presets[resolution] ?? "Moyenne";
  }

  // === NOUVELLES MÉTHODES POUR FLASH, GPS, TIMER ===

  Future<void> toggleFlash() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception("Caméra non initialisée");
      }

      final flashModes = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
      final currentIndex = flashModes.indexOf(_flashMode);
      final nextIndex = (currentIndex + 1) % flashModes.length;
      
      _flashMode = flashModes[nextIndex];
      await _controller!.setFlashMode(_flashMode);
      
      _addLog("Flash ${_getFlashModeName(_flashMode)}");
      _notifyStatsUpdate();
    } catch (e) {
      _addLog("Erreur flash: $e");
      rethrow;
    }
  }

  String _getFlashModeName(FlashMode mode) {
    final modes = {
      FlashMode.off: "désactivé",
      FlashMode.auto: "automatique",
      FlashMode.always: "toujours activé",
      FlashMode.torch: "torche",
    };
    return modes[mode] ?? "inconnu";
  }

  Future<void> setTimer(int seconds) async {
    _timerSeconds = seconds;
    _addLog("Minuterie réglée sur $seconds secondes");
  }

  Future<void> _startGPSTracking() async {
    try {
      // Vérifier les permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception("Services de localisation désactivés");
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Permissions de localisation refusées");
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception("Permissions de localisation définitivement refusées");
      }

      // Démarrer le tracking GPS
      _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        try {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
          );
          _currentPosition = position;
          _addLog("Position mise à jour: ${position.latitude}, ${position.longitude}");
        } catch (e) {
          _addLog("Erreur mise à jour GPS: $e");
        }
      });

      // Obtenir la position initiale
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _currentPosition = position;
      _gpsEnabled = true;
      _addLog("GPS activé: ${position.latitude}, ${position.longitude}");
    } catch (e) {
      _addLog("Erreur activation GPS: $e");
      rethrow;
    }
  }

  Future<void> _stopGPSTracking() async {
    _gpsTimer?.cancel();
    _gpsEnabled = false;
    _currentPosition = null;
    _addLog("GPS désactivé");
  }

  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _updateStatus("Serveur démarré sur le port $port");
      _addLog("Serveur démarré sur le port $port");
      
      _server!.listen((HttpRequest request) async {
        final clientIP = request.connectionInfo!.remoteAddress.address;
        final clientPort = request.connectionInfo!.remotePort;
        final clientId = "$clientIP:$clientPort";
        
        if (!_connectedClients.contains(clientId)) {
          _connectedClients.add(clientId);
          _totalConnections++;
          _notifyStatsUpdate();
          _addLog("Nouveau client connecté: $clientId");
        }

        try {
          // Gestion CORS
          _setCORSHeaders(request.response);

          if (request.method == 'OPTIONS') {
            await request.response.close();
            return;
          }

          // Routes principales
          if (request.uri.path == '/status' && request.method == 'GET') {
            await _handleStatusRequest(request);
          } else if (request.uri.path == '/info' && request.method == 'GET') {
            await _handleInfoRequest(request);
          } else if (request.uri.path == '/capture' && request.method == 'POST') {
            await _handleCaptureRequest(request);
          } else if (request.uri.path == '/record/start' && request.method == 'POST') {
            await _handleStartRecording(request);
          } else if (request.uri.path == '/record/stop' && request.method == 'POST') {
            await _handleStopRecording(request);
          } else if (request.uri.path == '/stream/start' && request.method == 'POST') {
            await _handleStartStream(request);
          } else if (request.uri.path == '/stream/stop' && request.method == 'POST') {
            await _handleStopStream(request);
          } else if (request.uri.path == '/switch-camera' && request.method == 'POST') {
            await _handleSwitchCamera(request);
          } else if (request.uri.path == '/resolution' && request.method == 'POST') {
            await _handleChangeResolution(request);
          }
          else if (request.uri.path == '/stream' && request.method == 'GET') {
          await _handleStreamRequest(request);
          }
          // Nouvelles routes pour flash, timer, GPS
          else if (request.uri.path == '/flash' && request.method == 'POST') {
            await _handleFlashRequest(request);
          } else if (request.uri.path == '/timer' && request.method == 'POST') {
            await _handleTimerRequest(request);
          } else if (request.uri.path == '/gps/start' && request.method == 'POST') {
            await _handleGPSStart(request);
          } else if (request.uri.path == '/gps/stop' && request.method == 'POST') {
            await _handleGPSStop(request);
          } else if (request.uri.path == '/gps/location' && request.method == 'GET') {
            await _handleGPSLocation(request);
          } else if (request.uri.path == '/gps/share' && request.method == 'POST') {
            await _handleGPSShare(request);
          } else {
            await _sendJsonResponse(
            request.response,
           {'error': 'Endpoint non trouvé', 'path': request.uri.path},
           statusCode: 404
          );
        }
        } catch (e) {
          _addLog("Erreur traitement requête: $e");
          request.response.statusCode = 500;
          request.response.write(json.encode({'error': 'Erreur interne: $e'}));
          await request.response.close();
        }
      });
    } catch (e) {
      _updateStatus("Erreur serveur: $e");
      _addLog("Erreur démarrage serveur: $e");
      rethrow;
    }
  }

 // REMPLACER la boucle while dans _handleStreamRequest
  // VERSION ALTERNATIVE avec gestion d'état manuelle
 Future<void> _handleStreamRequest(HttpRequest request) async {
  if (_controller == null || !_controller!.value.isInitialized) {
    await _sendJsonResponse(
      request.response,
      {'error': 'Caméra non initialisée'},
      statusCode: 503
    );
    return;
  }

  bool isClientConnected = true;
  int frameCount = 0;
  int errorCount = 0;
  const maxErrors = 10; // Augmenté de 5 à 10

  try {
    request.response
      ..statusCode = 200
      ..headers.set('Content-Type', 'multipart/x-mixed-replace; boundary=--jpgboundary')
      ..headers.set('Cache-Control', 'no-cache, no-store, must-revalidate')
      ..headers.set('Pragma', 'no-cache')
      ..headers.set('Expires', '0')
      ..headers.set('Connection', 'close')
      ..headers.set('Access-Control-Allow-Origin', '*');

    _addLog('🔴 Début streaming MJPEG pour ${request.connectionInfo!.remoteAddress.address}');

    while (_isStreaming && isClientConnected && errorCount < maxErrors) {
      try {
        // CORRECTION: Capturer une frame
        final frameBytes = await _captureFrameBytes();
        
        if (frameBytes == null || frameBytes.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
          errorCount++;
          continue;
        }

        // CORRECTION: Vérifier la taille de l'image
        if (frameBytes.length < 1024) {
          _addLog('⚠️ Frame trop petite: ${frameBytes.length} bytes');
          await Future.delayed(const Duration(milliseconds: 200));
          errorCount++;
          continue;
        }

        // Format MJPEG correct avec boundary
        final boundary = '--jpgboundary\r\n';
        final contentType = 'Content-Type: image/jpeg\r\n';
        final contentLength = 'Content-Length: ${frameBytes.length}\r\n\r\n';
        
        // CORRECTION: Écrire en une seule fois pour éviter la fragmentation
        final fullFrame = StringBuffer();
        fullFrame.write(boundary);
        fullFrame.write(contentType);
        fullFrame.write(contentLength);
        
        request.response.write(fullFrame.toString());
        request.response.add(frameBytes);
        request.response.write('\r\n');
        
        // CRITIQUE: Flush APRÈS avoir tout écrit
        await request.response.flush();
        
        frameCount++;
        errorCount = 0;
        
        // CORRECTION: Augmenter le délai entre frames (10 FPS au lieu de 15)
        await Future.delayed(const Duration(milliseconds: 100)); // 10 FPS

      } catch (e) {
        if (_isClientDisconnectedError(e)) {
          _addLog('📱 Client déconnecté');
          isClientConnected = false;
          break;
        }
        
        errorCount++;
        _addLog('⚠️ Erreur frame $frameCount: $e');
        
        if (errorCount >= maxErrors) {
          _addLog('❌ Trop d\'erreurs, arrêt du streaming');
          break;
        }
        
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

  } catch (e) {
    _addLog('❌ Erreur streaming: $e');
  } finally {
    _addLog('🟢 Streaming terminé - $frameCount frames envoyées');
    try {
      await request.response.close();
    } catch (_) {}
  }
}

// Méthode utilitaire pour détecter les déconnexions
 bool _isClientDisconnectedError(dynamic error) {
  final errorString = error.toString().toLowerCase();
  return error is SocketException ||
         error is HttpException ||
         errorString.contains('broken pipe') ||
         errorString.contains('connection closed') ||
         errorString.contains('connection reset') ||
         errorString.contains('software caused connection abort');
}

// NOUVELLE méthode pour capturer les frames en mémoire
 Future<Uint8List?> _captureFrameBytes() async {
  const maxRetries = 3;
  int attempt = 0;
  
  while (attempt < maxRetries) {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        return null;
      }

      final XFile imageFile = await _controller!.takePicture();
      final File file = File(imageFile.path);
      
      if (!await file.exists()) {
        attempt++;
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      
      final int fileSize = await file.length();
      if (fileSize == 0 || fileSize < 1024) {
        await file.delete();
        attempt++;
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      
      // CORRECTION: Attendre que le fichier soit complètement écrit
      await Future.delayed(const Duration(milliseconds: 10));
      
      final Uint8List imageBytes = await file.readAsBytes();
      
      // Supprimer le fichier
      try {
        await file.delete();
      } catch (e) {
        _addLog('⚠️ Impossible de supprimer ${imageFile.path}');
      }
      
      // CORRECTION: Validation stricte
      if (!_isValidJpeg(imageBytes)) {
        _addLog('⚠️ JPEG invalide, nouvelle tentative');
        attempt++;
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      
      return imageBytes;
      
    } catch (e) {
      _addLog('⚠️ Erreur capture tentative ${attempt + 1}: $e');
      attempt++;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
  
  return null;
}

  Future<void> testEncodingResponse() async {
    final testData = {
      'test': 'Données de test',
      'status': 'Test réussi',
      'encoding': 'UTF-8',
      'timestamp': DateTime.now().toString(),
    };
    
    // Test 1: Encodage manuel
    final jsonString = json.encode(testData);
    _addLog('JSON brut: $jsonString');
    
    // Test 2: Encodage UTF-8
    final utf8Bytes = utf8.encode(jsonString);
    _addLog('UTF-8 bytes length: ${utf8Bytes.length}');
    
    // Test 3: Décodage
    final decoded = utf8.decode(utf8Bytes);
    _addLog('Décodé: $decoded');
    
    _addLog('✅ Test d\'encodage réussi');
  }

  // CORRECTION : Méthode pour envoyer des réponses JSON de manière sûre
  Future<void> _sendJsonResponse(HttpResponse response, Map<String, dynamic> data, {int statusCode = 200}) async {
    try {
      response.statusCode = statusCode;
      _setCORSHeaders(response);
      
      // Encoder en JSON puis en UTF-8
      final jsonString = json.encode(data);
      final utf8Bytes = utf8.encode(jsonString);
      
      response.add(utf8Bytes);
      await response.close();
    } catch (e) {
      _addLog('❌ Erreur envoi réponse: $e');
      response.statusCode = 500;
      response.write(json.encode({'error': 'Erreur serveur interne'}));
      await response.close();
    }
  }

  // Dans server.dart - Validation JPEG
 bool _isValidJpeg(Uint8List bytes) {
  if (bytes.length < 4) return false;
  return bytes[0] == 0xFF && 
         bytes[1] == 0xD8 && 
         bytes[bytes.length - 2] == 0xFF && 
         bytes[bytes.length - 1] == 0xD9;
}

  // EXEMPLE d'utilisation dans _handleStatusRequest
  Future<void> _handleStatusRequest(HttpRequest request) async {
    final status = {
      'streaming': _isStreaming,
      'recording': _isRecording,
      'camera_ready': _controller?.value.isInitialized ?? false,
      'status': _status,
      'clients': _connectedClients.length,
      'total_connections': _totalConnections,
      'photos_captured': _photosCaptured,
      'videos_recorded': _videosRecorded,
      'resolution': _currentResolution,
      'camera_name': _controller?.description.name ?? 'Inconnue',
      'flash_mode': _getFlashModeName(_flashMode),
      'gps_enabled': _gpsEnabled,
      'timer_seconds': _timerSeconds,
      'current_location': _currentPosition != null 
          ? '${_currentPosition!.latitude}, ${_currentPosition!.longitude}'
          : 'Non disponible',
    };
    
    // Utiliser la nouvelle méthode sécurisée
    await _sendJsonResponse(request.response, status);
  }

  // 1. CORRECTION: Méthode _handleInfoRequest
  Future<void> _handleInfoRequest(HttpRequest request) async {
    final info = {
      'server_version': '1.0.0',
      'port': port,
      'available_cameras': _cameras?.length ?? 0,
      'current_camera': _controller?.description.name ?? 'Inconnue',
      'supported_resolutions': ['low', 'medium', 'high', 'veryHigh', 'ultraHigh', 'max'],
      'clients_connected': _connectedClients.length,
      'server_uptime': DateTime.now().toString(),
      'gps_supported': true,
      'flash_supported': true,
      'timer_supported': true,
    };
    
    // CORRECTION: Utiliser _sendJsonResponse au lieu de write
    await _sendJsonResponse(request.response, info);
  }

  Future<void> _handleCaptureRequest(HttpRequest request) async {
    try {
      if (_controller != null && _controller!.value.isInitialized) {
        print('Camera iniatialise');

        if(isStreaming) {
          print("Streaming en cours");
          await _sendJsonResponse(
            request.response, 
            {'error': 'Streaming en cours'},
            statusCode: 503
          );
          return;
        }
        
        // Gestion du timer
        if (_timerSeconds > 0) {
          _addLog("Déclenchement dans $_timerSeconds secondes...");
          await Future.delayed(Duration(seconds: _timerSeconds));
        }

        final image = await _controller!.takePicture();
        final file = File(image.path);
        final imageBytes = await file.readAsBytes();
        
        request.response.headers.set('Content-Type', 'image/jpeg');
        request.response.add(imageBytes);
        await request.response.close();
        
        _photosCaptured++;
        _notifyStatsUpdate();
        _addLog("Photo capturée par ${request.connectionInfo!.remoteAddress.address}");
      } else {
        throw Exception('Caméra non initialisée');
      }
    } catch (e) {
      await _sendJsonResponse(
        request.response, 
        {'error': 'Erreur capture: $e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleStartRecording(HttpRequest request) async {
    try {
      if (_controller != null && !_isRecording) {
        await _controller!.startVideoRecording();
        _isRecording = true;
        _updateStatus("Enregistrement démarré");
        
        await _sendJsonResponse(request.response, {
          'success': true,
          'status': 'recording_started',
          'timestamp': DateTime.now().toString()
        });
        
        _addLog("Enregistrement démarré");
      } else {
        throw Exception('Caméra non disponible ou déjà en enregistrement');
      }
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleStopRecording(HttpRequest request) async {
    try {
      if (_controller != null && _isRecording) {
        final file = await _controller!.stopVideoRecording();
        _isRecording = false;
        _updateStatus("Enregistrement arrêté");
        _videosRecorded++;
        _notifyStatsUpdate();
        request.response.write(json.encode({
          'status': 'recording_stopped', 
          'path': file.path,
          'timestamp': DateTime.now().toString()
        }));
        _addLog("Enregistrement arrêté - Fichier: ${file.path}");
      } else {
        throw Exception('Aucun enregistrement en cours');
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write(json.encode({'error': '$e'}));
    }
    await request.response.close();
  }

  Future<void> _handleStartStream(HttpRequest request) async {
    _isStreaming = true;
    _updateStatus("Streaming démarré");
    
    await _sendJsonResponse(request.response, {
      'success': true,
      'status': 'stream_started',
      'timestamp': DateTime.now().toString()
    });
    
    _addLog("Streaming démarré");
  }

  Future<void> _handleStopStream(HttpRequest request) async {
    _isStreaming = false;
    _updateStatus("Streaming arrêté");
    
    await _sendJsonResponse(request.response, {
      'success': true,
      'status': 'stream_stopped',
      'timestamp': DateTime.now().toString()
    });
    
    _addLog("Streaming arrêté");
  }

  Future<void> _handleSwitchCamera(HttpRequest request) async {
    try {
      await switchCamera();
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'camera_switched', 
        'camera': _controller?.description.name,
        'timestamp': DateTime.now().toString()
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleChangeResolution(HttpRequest request) async {
    try {
      final body = await _readRequestBody(request);
      final resolution = body['resolution'] ?? 'medium';
      
      final preset = _getResolutionPreset(resolution);
      await changeResolution(preset);
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'resolution_changed',
        'resolution': _currentResolution
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  ResolutionPreset _getResolutionPreset(String resolution) {
    final presets = {
      'low': ResolutionPreset.low,
      'medium': ResolutionPreset.medium,
      'high': ResolutionPreset.high,
      'veryHigh': ResolutionPreset.veryHigh,
      'ultraHigh': ResolutionPreset.ultraHigh,
      'max': ResolutionPreset.max,
    };
    return presets[resolution] ?? ResolutionPreset.medium;
  }

  // === NOUVEAUX HANDLERS POUR FLASH, TIMER, GPS ===

  Future<void> _handleFlashRequest(HttpRequest request) async {
    try {
      await toggleFlash();
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'flash_changed',
        'flash_mode': _getFlashModeName(_flashMode),
        'flash_enabled': _flashMode != FlashMode.off
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleTimerRequest(HttpRequest request) async {
    try {
      final body = await _readRequestBody(request);
      final seconds = body['seconds'] ?? 0;
      
      await setTimer(seconds);
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'timer_set',
        'seconds': seconds
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleGPSStart(HttpRequest request) async {
    try {
      await _startGPSTracking();
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'gps_started',
        'location': _currentPosition != null 
            ? '${_currentPosition!.latitude}, ${_currentPosition!.longitude}'
            : 'En cours d\'acquisition'
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleGPSStop(HttpRequest request) async {
    try {
      await _stopGPSTracking();
      
      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'gps_stopped'
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleGPSLocation(HttpRequest request) async {
    try {
      if (!_gpsEnabled) {
        throw Exception('GPS non activé');
      }

      if (_currentPosition == null) {
        throw Exception('Position non disponible');
      }

      await _sendJsonResponse(request.response, {
        'success': true,
        'status': 'location_obtained',
        'location': '${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'accuracy': _currentPosition!.accuracy,
        'altitude': _currentPosition!.altitude,
        'speed': _currentPosition!.speed,
        'timestamp': _currentPosition!.timestamp.toString()
      });
    } catch (e) {
      await _sendJsonResponse(
        request.response,
        {'success': false, 'error': '$e'},
        statusCode: 500
      );
    }
  }

  Future<void> _handleGPSShare(HttpRequest request) async {
  try {
    final body = await _readRequestBody(request);
    final location = body['location'] ?? 'Position inconnue';

    // Si la position est au format "latitude, longitude", créer un lien Google Maps
    String googleMapsUrl = '';
    
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length == 2) {
        final lat = parts[0].trim();
        final lon = parts[1].trim();
        googleMapsUrl = 'https://www.google.com/maps?q=$lat,$lon';
      }
    }

    _addLog("Position partagée: $location -> $googleMapsUrl");

    await _sendJsonResponse(request.response, {
      'success': true,
      'status': 'location_shared',
      'location': location,
      'google_maps_url': googleMapsUrl,  // Nouveau champ avec le lien
      'timestamp': DateTime.now().toString()
    });
  } catch (e) {
    await _sendJsonResponse(
      request.response,
      {'success': false, 'error': '$e'},
      statusCode: 500
    );
  }
}

  Future<Map<String, dynamic>> _readRequestBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    return json.decode(content);
  }

  void _updateStatus(String newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().split(' ')[1].split('.')[0];
    final logMessage = "[$timestamp] $message";
    _logMessages.insert(0, logMessage);
    if (_logMessages.length > 100) {
      _logMessages.removeLast();
    }
    _logController.add(logMessage);
  }

  void _notifyStatsUpdate() {
    final stats = {
      'clients': _connectedClients.length,
      'total_connections': _totalConnections,
      'photos_captured': _photosCaptured,
      'videos_recorded': _videosRecorded,
      'resolution': _currentResolution,
      'flash_mode': _getFlashModeName(_flashMode),
      'gps_enabled': _gpsEnabled,
    };
    _statsController.add(stats);
  }

  Future<void> stopServer() async {
    _addLog("Arrêt du serveur en cours...");
    
    // Arrêter tous les timers
    _gpsTimer?.cancel();
    _captureTimer?.cancel();
    
    // Arrêter le GPS
    if (_gpsEnabled) {
      await _stopGPSTracking();
    }
    
    // Arrêter l'enregistrement si actif
    if (_isRecording && _controller != null) {
      try {
        await _controller!.stopVideoRecording();
      } catch (e) {
        _addLog("Erreur arrêt enregistrement: $e");
      }
    }
    
    // Fermer le serveur et la caméra
    await _server?.close();
    await _controller?.dispose();
    
    _server = null;
    _isStreaming = false;
    _isRecording = false;
    _updateStatus("Serveur arrêté");
    _addLog("Serveur arrêté");
  }

  void clearLogs() {
    _logMessages.clear();
    _addLog("Journaux effacés");
  }

  String getServerAddress() {
    try {
      final interfaces = NetworkInterface.list();
      return "Serveur actif sur le port $port";
    } catch (e) {
      return "Adresse non disponible: $e";
    }
  }

  Future<void> dispose() async {
    await stopServer();
    await _statusController.close();
    await _statsController.close();
    await _logController.close();
  }
}