import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Nécessaire pour encoder/décoder en JSON

/// Un modèle simple pour représenter un appareil dans l'historique.
class DeviceHistory {
  final String name;
  final String address;
  final String connectionType; // 'bluetooth' ou 'wifi'
  final DateTime lastConnected;

  DeviceHistory({
    required this.name,
    required this.address,
    required this.connectionType,
    required this.lastConnected,
  });

  // Convertit l'objet en Map (pour le stockage JSON dans SharedPreferences)
  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'connectionType': connectionType,
        // Stocker la date au format ISO 8601 String
        'lastConnected': lastConnected.toIso8601String(),
      };

  // Crée un objet depuis un Map JSON (pour la lecture depuis SharedPreferences)
  factory DeviceHistory.fromJson(Map<String, dynamic> json) {
    return DeviceHistory(
      name: json['name'] as String,
      address: json['address'] as String,
      connectionType: json['connectionType'] as String,
      lastConnected: DateTime.parse(json['lastConnected'] as String),
    );
  }

  // Méthode pour créer une copie, utile si l'on veut rendre l'objet immutable
  DeviceHistory copyWith({
    String? name,
    String? address,
    String? connectionType,
    DateTime? lastConnected,
  }) {
    return DeviceHistory(
      name: name ?? this.name,
      address: address ?? this.address,
      connectionType: connectionType ?? this.connectionType,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}

/// Gère l'historique des appareils avec persistance via SharedPreferences.
class DeviceHistoryManager {
  static const String _historyKey = 'device_history';
  static const int _maxHistory = 10;

  // Cache en mémoire pour éviter de lire SharedPreferences à chaque fois
  List<DeviceHistory> _historyCache = [];
  bool _isLoaded = false;

  /// Charge l'historique depuis SharedPreferences. Doit être appelé avant getHistory.
  Future<void> loadHistory() async {
    if (_isLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final historyJsonString = prefs.getString(_historyKey);

    if (historyJsonString != null) {
      // Décoder la liste JSON stockée
      final List<dynamic> historyJsonList = jsonDecode(historyJsonString);
      _historyCache = historyJsonList
          .map((json) => DeviceHistory.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      _historyCache = [];
    }

    _sortHistory();
    _isLoaded = true;
  }

  /// Sauvegarde l'historique actuel dans SharedPreferences.
  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // Convertir la liste d'objets en liste JSON (Map)
    final List<Map<String, dynamic>> historyJsonList =
        _historyCache.map((d) => d.toJson()).toList();
    // Encoder la liste JSON en String pour le stockage
    final historyJsonString = jsonEncode(historyJsonList);

    await prefs.setString(_historyKey, historyJsonString);
  }

  /// Trie l'historique par date de dernière connexion (plus récent en premier).
  void _sortHistory() {
    _historyCache.sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
  }

  /// Ajoute un appareil à l'historique (ou le met à jour s'il existe déjà).
  Future<void> addDevice(DeviceHistory device) async {
    // S'assurer que les données sont chargées avant de modifier
    await loadHistory();

    // 1. Supprimer l'ancienne entrée si l'appareil (basé sur l'adresse) est déjà là
    _historyCache.removeWhere((d) => d.address == device.address);

    // 2. Ajouter la nouvelle entrée en haut de la liste avec la date actuelle
    _historyCache.insert(0, device.copyWith(lastConnected: DateTime.now()));

    // 3. Tronquer la liste si elle dépasse la taille maximale
    if (_historyCache.length > _maxHistory) {
      _historyCache.removeRange(_maxHistory, _historyCache.length);
    }

    // 4. Sauvegarder immédiatement les changements
    await _saveHistory();
  }

  /// Récupère l'historique. Assurez-vous d'appeler loadHistory() au préalable.
  List<DeviceHistory> getHistory() {
    // Retourne une copie pour éviter des modifications externes non tracées
    _sortHistory(); // Assurer le tri avant de retourner
    return List.unmodifiable(_historyCache);
  }

  /// Supprime un appareil spécifique de l'historique.
  Future<void> removeDevice(String address) async {
    await loadHistory();
    _historyCache.removeWhere((d) => d.address == address);
    await _saveHistory();
  }

  /// (Optionnel) Vider tout l'historique.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    _historyCache = [];
  }
}

/// Le Modal pour afficher l'historique des connexions.
class DeviceHistoryModal extends StatefulWidget {
  final Function(DeviceHistory device) onReconnect;
  // Le manager est maintenant passé pour interagir avec l'historique persistant
  final DeviceHistoryManager manager;

  const DeviceHistoryModal({
    Key? key,
    required this.onReconnect,
    required this.manager,
  }) : super(key: key);

  // Méthode statique pour afficher le modal facilement
  static void show({
    required BuildContext context,
    required DeviceHistoryManager manager, // Le manager doit être passé
    required Function(DeviceHistory device) onReconnect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DeviceHistoryModal(
        onReconnect: onReconnect,
        manager: manager,
      ),
    );
  }

  @override
  _DeviceHistoryModalState createState() => _DeviceHistoryModalState();
}

class _DeviceHistoryModalState extends State<DeviceHistoryModal> {
  DeviceHistoryManager get _manager => widget.manager;
  late Future<List<DeviceHistory>> _loadHistoryFuture;

  @override
  void initState() {
    super.initState();
    _loadHistoryFuture = _manager.loadHistory().then((_) => _manager.getHistory());
  }

  void _refreshHistory() {
    setState(() {
      _loadHistoryFuture = Future.value(_manager.getHistory());
    });
  }

  @override
Widget build(BuildContext context) {
  // Définir la largeur maximale : 600px est une taille standard pour un modal sur tablette/desktop.
  // Utilisez 90% de la largeur de l'écran sur mobile, mais pas plus de 600.
  final double maxWidth = MediaQuery.of(context).size.width > 600 
      ? 600.0 
      : MediaQuery.of(context).size.width * 0.9;
      
  return Center( // Centrer le ConstrainedBox sur l'écran
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      
      child: Container( // VOTRE CONTAINER D'ORIGINE
        margin: const EdgeInsets.all(20), // Utilisez const si possible
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.7,
        expand: false,
        builder: (_, scrollController) {
          return Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                _buildHeader(),
                SizedBox(height: 20),
                Expanded(
                  child: FutureBuilder<List<DeviceHistory>>(
                    future: _loadHistoryFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Chargement de l\'historique...',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Erreur de chargement',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Impossible de charger l\'historique',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final devices = snapshot.data ?? [];

                      if (devices.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.devices_other,
                                color: Colors.grey[400],
                                size: 64,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Aucun appareil enregistré',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  'Les appareils auxquels vous vous connectez apparaîtront ici pour une reconnexion rapide.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: devices.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Colors.grey[200],
                        ),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return _buildDeviceTile(device);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Poignée de drag
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(height: 20),
        // Titre
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history,
                color: Colors.blue,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appareils Connectés',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Historique de vos connexions récentes',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeviceTile(DeviceHistory device) {
    final timeAgo = _formatDuration(DateTime.now().difference(device.lastConnected));
    final isBluetooth = device.connectionType == 'bluetooth';

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _connectToDevice(device),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                // Icone et type de connexion
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isBluetooth ? Colors.blue[50] : Colors.green[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isBluetooth ? Icons.bluetooth : Icons.wifi,
                    color: isBluetooth ? Colors.blue : Colors.green,
                    size: 20,
                  ),
                ),
                SizedBox(width: 16),
                
                // Informations de l'appareil
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Text(
                        device.address,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Dernière connexion : $timeAgo',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                
                // Boutons d'action
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bouton de connexion rapide
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.link, color: Colors.green, size: 18),
                        onPressed: () => _connectToDevice(device),
                        tooltip: 'Se connecter',
                        padding: EdgeInsets.all(8),
                      ),
                    ),
                    SizedBox(width: 8),
                    
                    // Bouton de suppression
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        onPressed: () => _showDeleteDialog(device),
                        tooltip: 'Supprimer',
                        padding: EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _connectToDevice(DeviceHistory device) {
    Navigator.pop(context);
    widget.onReconnect(device);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Connexion à ${device.name}...'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showDeleteDialog(DeviceHistory device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirmer la suppression'),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment supprimer "${device.name}" de l\'historique ?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _manager.removeDevice(device.address);
              _refreshHistory();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('${device.name} supprimé de l\'historique'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// Fonction utilitaire pour un affichage de durée plus lisible
String _formatDuration(Duration duration) {
  if (duration.inMinutes < 1) return "à l'instant";
  if (duration.inHours < 1) return "${duration.inMinutes} min";
  if (duration.inDays < 1) return "${duration.inHours} h";
  if (duration.inDays < 30) return "${duration.inDays} j";
  if (duration.inDays < 365) return "${duration.inDays ~/ 30} mois";
  return "${duration.inDays ~/ 365} an${duration.inDays ~/ 365 > 1 ? 's' : ''}";
}