// Fichier: modal_connexion/wifi.dart

import 'package:flutter/material.dart';
import 'package:lali_project/services/Services.Wifi.dart';

class WifiConnectionModal extends StatefulWidget {
  final WiFiControlManager manager;

  const WifiConnectionModal({super.key, required this.manager});

  static Future<void> show({
    required BuildContext context,
    required WiFiControlManager manager,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return WifiConnectionModal(manager: manager);
      },
    );
  }

  @override
  State<WifiConnectionModal> createState() => _WifiConnectionModalState();
}

class _WifiConnectionModalState extends State<WifiConnectionModal> {
  final _ipController = TextEditingController(text: '10.153.123.53');
  final _portController = TextEditingController(text: '80');

  bool _useWebSocket = false;
  bool _isConnecting = false;
  String _statusMessage = '';
  ConnectionMode _currentMode = ConnectionMode.unknown;
  ConnectionErrorType _lastErrorType = ConnectionErrorType.none;

  @override
  void initState() {
    super.initState();
    _getNetworkInfo();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _getNetworkInfo() async {
    try {
      final connectivity = await widget.manager.checkWifiConnectivity();
      final localIp = await widget.manager.getLocalWifiIp();
      final gatewayIp = await widget.manager.getWifiGatewayIp();

      if (mounted) {
        setState(() {
          _currentMode = connectivity.mode;

          if (connectivity.isConnected) {
            _statusMessage = '✅ ${_getModeDisplayName(connectivity.mode)}\n'
                'IP locale: ${localIp ?? "Non disponible"}\n'
                'Passerelle: ${gatewayIp ?? "Non disponible"}';
          } else {
            _statusMessage = '❌ Aucune connexion réseau détectée\n'
                'Connectez-vous au WiFi ou activez le hotspot';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '⚠️ État inconnu\nTentative de connexion possible';
        });
      }
    }
  }

  String _getModeDisplayName(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.wifi:
        return '🔗 Mode Wi-Fi';
      case ConnectionMode.hotspot:
        return '📱 Mode Hotspot';
      case ConnectionMode.unknown:
        return '❓ Mode Inconnu';
    }
  }

  String _getErrorMessage(ConnectionErrorType errorType, ConnectionMode mode) {
    switch (errorType) {
      case ConnectionErrorType.invalidIpOrPort:
        return 'Adresse IP ou port non valide';
      case ConnectionErrorType.wifiNotConnected:
        return 'Wi-Fi non connecté';
      case ConnectionErrorType.hotspotNotActive:
        return 'Hotspot non actif';
      case ConnectionErrorType.connectionFailed:
        return 'Connexion refusée - Vérifiez l\'IP/port';
      case ConnectionErrorType.protocolError:
        return 'Erreur de protocole';
      case ConnectionErrorType.timeout:
        return 'Timeout de connexion';
      case ConnectionErrorType.dnsLookupFailed:
        return 'Impossible de résoudre l\'adresse';
      case ConnectionErrorType.sslError:
        return 'Erreur de sécurité SSL';
      case ConnectionErrorType.unauthorized:
        return 'Accès non autorisé';
      case ConnectionErrorType.forbidden:
        return 'Accès interdit';
      case ConnectionErrorType.notFound:
        return 'Ressource non trouvée';
      case ConnectionErrorType.serverError:
        return 'Erreur serveur';
      case ConnectionErrorType.unknown:
        return 'Erreur inconnue';
      case ConnectionErrorType.none:
        return 'Aucune erreur';
    }
  }

  Color _getStatusColor() {
    if (_statusMessage.startsWith('✅')) return Colors.green[700]!;
    if (_statusMessage.startsWith('❌')) return Colors.red[700]!;
    if (_statusMessage.startsWith('⚠️')) return Colors.orange[700]!;
    return Colors.grey[700]!;
  }

  Future<void> _connect() async {
    if (_isConnecting) return;

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (port == null) {
      setState(() => _statusMessage = '❌ Erreur : Port invalide');
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connexion en cours...';
    });

    try {
      ConnectionResult result;

      if (_useWebSocket) {
        result = await widget.manager.connectWebSocket(ip, port: port);
      } else {
        result = await widget.manager.connectHttp(ip, port: port);
      }

      setState(() {
        _isConnecting = false;
        _currentMode = result.connectionMode;
        _lastErrorType = result.errorType;

        if (result.success) {
          _statusMessage = '✅ Connexion réussie!\n${result.message}';
        } else {
          final errorMsg = _getErrorMessage(result.errorType, result.connectionMode);
          _statusMessage = '❌ Échec: $errorMsg';
        }
      });

      if (result.success) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '❌ Erreur: ${e.toString()}';
        _lastErrorType = ConnectionErrorType.unknown;
      });
    }
  }

  Future<void> _testConnection() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Test de connexion...';
    });

    try {
      final result = await widget.manager.testDeviceConnection();
      
      setState(() {
        _isConnecting = false;
        if (result.success) {
          _statusMessage = '✅ Test réussi!\n${result.message}';
        } else {
          _statusMessage = '❌ Test échoué: ${result.message}';
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '❌ Erreur test: ${e.toString()}';
      });
    }
  }

  Future<void> _sendTestCommand() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Envoi de commande test...';
    });

    try {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 80;
      
      final result = await widget.manager.sendHttpCommand(
        ip: ip,
        port: port,
        command: 'status',
        timeout: const Duration(seconds: 5),
      );

      setState(() {
        _isConnecting = false;
        _currentMode = result.connectionMode;
        _lastErrorType = result.errorType;

        if (result.success) {
          _statusMessage = '✅ Commande réussie!\n${result.message}';
        } else {
          final errorMsg = _getErrorMessage(result.errorType, result.connectionMode);
          _statusMessage = '❌ Échec commande: $errorMsg';
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '❌ Erreur commande: ${e.toString()}';
      });
    }
  }

  Future<void> _refreshNetworkInfo() async {
    setState(() {
      _statusMessage = 'Actualisation en cours...';
    });

    try {
      final connectivity = await widget.manager.checkWifiConnectivity();
      final localIp = await widget.manager.getLocalWifiIp();
      final gatewayIp = await widget.manager.getWifiGatewayIp();

      if (mounted) {
        setState(() {
          _currentMode = connectivity.mode;
          if (connectivity.isConnected) {
            _statusMessage = '✅ ${_getModeDisplayName(connectivity.mode)}\n'
                'IP locale: ${localIp ?? "Non disponible"}\n'
                'Passerelle: ${gatewayIp ?? "Non disponible"}';
          } else {
            _statusMessage = '❌ Aucune connexion réseau détectée';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '❌ Erreur actualisation: ${e.toString()}';
        });
      }
    }
  }

  Widget _buildConnectionModeIndicator() {
    Color color;
    IconData icon;
    String text;

    switch (_currentMode) {
      case ConnectionMode.wifi:
        color = Colors.blue;
        icon = Icons.wifi;
        text = 'Wi-Fi';
      case ConnectionMode.hotspot:
        color = Colors.green;
        icon = Icons.wifi_channel;
        text = 'Hotspot';
      case ConnectionMode.unknown:
        color = Colors.grey;
        icon = Icons.warning;
        text = 'Non connecté';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final protocolText = _useWebSocket ? 'WebSocket (ws://)' : 'HTTP (http://)';
    final protocolIcon = _useWebSocket ? Icons.cloud_circle : Icons.public;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titre et poignée
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Connexion Device',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildConnectionModeIndicator(),
              ],
            ),
            const Divider(height: 25),

            // 1. Sélecteur de Protocole
            Row(
              children: [
                Icon(protocolIcon, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Protocole : $protocolText',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: _useWebSocket,
                  onChanged: _isConnecting
                      ? null
                      : (bool value) {
                          setState(() {
                            _useWebSocket = value;
                            _portController.text = value ? '81' : '80';
                            _statusMessage = '';
                          });
                        },
                  activeColor: Colors.blue,
                ),
                Text(_useWebSocket ? 'WS' : 'HTTP'),
              ],
            ),
            const SizedBox(height: 15),

            // 2. Champs IP et Port
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    enabled: !_isConnecting,
                    decoration: InputDecoration(
                      labelText: 'Adresse IP du Device',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.wifi),
                      hintText: '10.153.123.53',
                      errorText: _ipController.text.isEmpty ? 'Requis' : null,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    enabled: !_isConnecting,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      hintText: '80',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // IPs courantes
            Wrap(
              spacing: 8,
              children: [
                _buildIpChip('10.153.123.53'),
                _buildIpChip('10.153.123.53'),
                _buildIpChip('10.0.0.1'),
              ],
            ),
            const SizedBox(height: 15),

            // 3. Boutons d'action
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnecting ? null : _refreshNetworkInfo,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnecting ? null : _testConnection,
                    icon: const Icon(Icons.wifi_find, size: 16),
                    label: const Text('Tester'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnecting ? null : _sendTestCommand,
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Commande Test'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting ? null : _connect,
                    icon: _isConnecting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.cast_connected, size: 18),
                    label: Text(
                      _isConnecting ? 'Connexion...' : 'Connecter',
                      style: const TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // 4. Statut/Messages d'erreur
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getStatusColor().withOpacity(0.3)),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _getStatusColor(),
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            ),

            // 5. Informations de débogage
            if (_lastErrorType != ConnectionErrorType.none && !_isConnecting)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Type d\'erreur: ${_lastErrorType.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),

            const Spacer(),
            
            // 6. Instructions selon le mode
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📋 Instructions ${_currentMode == ConnectionMode.wifi ? 'Wi-Fi' : 'Hotspot'}:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentMode == ConnectionMode.wifi 
                      ? '1. Connectez-vous au même réseau WiFi que le device\n'
                        '2. Entrez l\'IP locale du device\n'
                        '3. Cliquez sur "Connecter" ou "Tester"'
                      : '1. Activez le hotspot sur le device\n'
                        '2. Connectez-vous au réseau WiFi du device\n'
                        '3. Entrez l\'IP du device (souvent 10.153.123.53)\n'
                        '4. Cliquez sur "Connecter"',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),

            // 7. Info détection automatique
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Détection automatique des types de microcontrôleurs',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                      ),
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

  Widget _buildIpChip(String ip) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _ipController.text = ip;
        });
      },
      child: Chip(
        label: Text(ip),
        backgroundColor: Colors.grey[100],
        labelStyle: const TextStyle(fontSize: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}