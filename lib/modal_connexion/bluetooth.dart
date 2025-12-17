import 'package:flutter/material.dart';
import 'dart:async';

import 'package:lali_project/services/blue_manager.dart'; // Assurez-vous que le chemin est correct
import 'package:lali_project/connexion/bluetooth/blue_plus.dart'; // Pour le modèle BluetoothDevice BLE

/// Un widget Modal pour gérer le scan et la sélection des appareils Bluetooth (Classic/BLE).
class BluetoothModal extends StatefulWidget {
  final BluetoothManager manager;
  final Function(dynamic device) onDeviceSelected;

  const BluetoothModal({
    super.key,
    required this.manager,
    required this.onDeviceSelected,
  });

  /// Méthode statique pour afficher le modal facilement
  static Future<void> show({
    required BuildContext context,
    required BluetoothManager manager,
    required Function(dynamic device) onDeviceSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Important pour le design
      builder: (context) {
        return BluetoothModal(
          manager: manager,
          onDeviceSelected: onDeviceSelected,
        );
      },
    );
  }

  @override
  State<BluetoothModal> createState() => _BluetoothModalState();
}

class _BluetoothModalState extends State<BluetoothModal> {
  // Liste interne pour stocker les appareils découverts
  List<dynamic> _discoveredDevices = [];
  bool _isScanning = false;
  String? _errorMessage; // Pour gérer et afficher les erreurs principales

  dynamic _selectedDevice; // L'appareil sur lequel l'utilisateur a cliqué
  String? _connectionStatusMessage;

  late StreamSubscription _deviceStreamSubscription;
  late StreamSubscription _messageStreamSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToStreams();
    _initializeAndScan();
  }

  /// Initialise les écouteurs de streams
  void _subscribeToStreams() {
    // 1. Écouter les appareils découverts (met à jour la liste)
    _deviceStreamSubscription =
        widget.manager.discoveredDevicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
          _errorMessage = null; // Supprimer l'erreur si des appareils arrivent
        });
      }
    });

    // 2. Écouter les messages/erreurs (pour le feedback utilisateur)
    _messageStreamSubscription = widget.manager.messageStream.listen((message) {
      if (mounted) {
        // Détecter si c'est une erreur critique de l'initialisation/scan
        if (message.contains('Échec') || message.contains('Erreur')) {
          setState(() {
            _errorMessage = message;
          });
        }
        // Afficher les messages d'état (même les erreurs) comme un SnackBar pour la visibilité
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }

  /// Tente d'initialiser le Bluetooth et démarre le scan Classic par défaut.
  /// Tente d'initialiser le Bluetooth et démarre le scan Classic par défaut.
// bluetooth.dart

Future<void> _initializeAndScan() async {
  try {
    await widget.manager.initialize(); // Vérifie les permissions et l'état
    
    // --- VÉRIFICATION DE L'ACTIVATION ---
    bool isEnabled = await widget.manager.isBluetoothEnabled();
    if (!isEnabled) {
        // 1. Informer l'utilisateur
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Veuillez activer le Bluetooth pour continuer le scan.')),
        );
        // 2. Ouvrir les paramètres/dialogue d'activation
        await widget.manager.openBluetoothSettings(); // Utilise la méthode mise à jour
        
        // 3. Mettre à jour l'UI pour refléter l'état désactivé
        if (mounted) {
            setState(() {
                _isScanning = false;
                _errorMessage = 'Bluetooth désactivé. Veuillez l\'activer.';
            });
        }
        return; // Arrêter le processus
    }
    // --- FIN VÉRIFICATION ---

    _setAndStartScan(BluetoothType.classic); // Scan par défaut si tout est OK
  } catch (e) {
    // ... (Gestion d'erreur existante)
  }
}

  @override
  void dispose() {
    widget.manager.stopScan();
    _deviceStreamSubscription.cancel();
    _messageStreamSubscription.cancel();
    super.dispose();
  }

  /// Change le type de Bluetooth et démarre le scan
// bluetooth.dart

Future<void> _setAndStartScan(BluetoothType type) async {
  if (_isScanning) return; 

  // --- VÉRIFICATION DE L'ACTIVATION ---
  bool isEnabled = await widget.manager.isBluetoothEnabled();
  if (!isEnabled) {
      if (mounted) {
        setState(() {
            _isScanning = false;
            _errorMessage = 'Bluetooth désactivé. Veuillez l\'activer.';
        });
        // 1. Informer l'utilisateur
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Veuillez activer le Bluetooth pour lancer le scan.')),
        );
        // 2. Ouvrir les paramètres/dialogue d'activation
        await widget.manager.openBluetoothSettings(); // Utilise la méthode mise à jour
      }
      return; // Arrêter le scan
  }
  
  // Mettre à jour le type et l'état
  widget.manager.setBluetoothType(type);
  if (mounted) {
    setState(() {
      _isScanning = true;
      _discoveredDevices = []; // Vider la liste
      _errorMessage = null; // Réinitialiser l'erreur
    });
  }

  try {
    // Le manager doit pouvoir faire la distinction entre Classic et BLE
    // et démarrer le scan approprié.
    await widget.manager.startScan();
  } catch (e) {
    // ... (Gestion d'erreur existante)
    // Le message d'erreur est géré par le messageStream et affiché
    await widget.manager.stopScan();
  } finally {
    // S'assurer que _isScanning passe à false après la durée du scan
    await Future.delayed(Duration(seconds: widget.manager.scanDuration + 1));
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }
}

// bluetooth.dart

// ... (Ajouter après _setAndStartScan)

/// Gère la connexion à l'appareil sélectionné
Future<void> _connectToSelectedDevice(dynamic device) async {
  // 1. Arrêter le scan et mettre à jour l'état
  widget.manager.stopScan();
  if (mounted) {
    setState(() {
      _selectedDevice = device;
      _connectionStatusMessage = 'Connexion à ${device.name}...';
    });
  }

  // 2. Tenter la connexion
  try {
    await widget.manager.connectToDevice(device);
    
    // 3. Connexion réussie : mettre à jour l'état final et fermer le modal
    if (mounted) {
      setState(() {
        _connectionStatusMessage = 'Connecté ! Fermeture du sélecteur...';
      });
    }

    // Attendre un court instant pour que l'utilisateur voie la réussite
    await Future.delayed(const Duration(milliseconds: 500)); 
    
    // Fermer le modal et appeler le callback
    if (mounted) {
      Navigator.pop(context);
      widget.onDeviceSelected(device); 
    }

  } catch (e) {
    // 4. Échec de la connexion : afficher l'erreur
    if (mounted) {
      setState(() {
        _connectionStatusMessage = 'Échec de connexion: ${e.toString().split(':')[0]}';
        _selectedDevice = null; // Remettre à zéro pour réactiver la liste
        
        // Afficher l'erreur de connexion dans un SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Échec: $_connectionStatusMessage')),
        );
      });
      // Le modal reste ouvert pour réessayer.
    }
  }
}

  /// Construit l'en-tête pour la sélection Classic/BLE
  Widget _buildHeader() {
    final currentType = widget.manager.bluetoothType;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      child: Column(
        children: [
          // Sélecteur de type
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTypeButton(
                type: BluetoothType.classic,
                label: 'Classic',
                isSelected: currentType == BluetoothType.classic,
              ),
              const SizedBox(width: 16),
              _buildTypeButton(
                type: BluetoothType.ble,
                label: 'BLE (Low Energy)',
                isSelected: currentType == BluetoothType.ble,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Indicateur de scan
          if (_isScanning)
            const LinearProgressIndicator()
          else
            Text(
              'Type sélectionné: ${currentType == BluetoothType.classic ? 'Classic' : 'BLE'} - Durée: ${widget.manager.scanDuration}s',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  /// Construit un bouton pour sélectionner le type Bluetooth
  Widget _buildTypeButton({
    required BluetoothType type,
    required String label,
    required bool isSelected,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: _isScanning || (widget.manager.bluetoothType == type && _isScanning == false)
            ? null // Désactiver si scan en cours ou si déjà sélectionné et scan terminé
            : () => _setAndStartScan(type),
        style: ElevatedButton.styleFrom(
          foregroundColor: isSelected ? Colors.white : Colors.black,
          backgroundColor: isSelected ? Colors.blue[600] : Colors.grey[200],
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }

  /// Construit le corps principal de la liste/erreur
  // bluetooth.dart

Widget _buildBody() {
  if (_errorMessage != null) {
    return _buildErrorState(_errorMessage!);
  }

  // --- NOUVEL ÉTAT : CONNEXION EN COURS ---
  // Si _connectionStatusMessage est défini, cela signifie qu'une connexion est en cours 
  // ou vient d'échouer, et nous affichons l'état au centre de l'écran.
  if (_connectionStatusMessage != null) {
    // Vérifie si l'état actuel est un succès/échec ou une tentative en cours
    final bool isConnecting = 
        _connectionStatusMessage!.startsWith('Connexion à');
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Afficher le spinner UNIQUEMENT si la connexion est en cours
          if (isConnecting) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
          ] else ...[
            // Afficher une icône de succès/échec
            Icon(
              _connectionStatusMessage!.startsWith('Échec') 
                ? Icons.error_outline 
                : Icons.check_circle_outline,
              size: 50,
              color: _connectionStatusMessage!.startsWith('Échec') 
                ? Colors.red 
                : Colors.green,
            ),
            const SizedBox(height: 16),
          ],
          
          // Afficher le message d'état de connexion
          Text(
            _connectionStatusMessage!, 
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          
          // Bouton de retour à la liste après un échec
          if (!isConnecting && _connectionStatusMessage!.startsWith('Échec') && _selectedDevice == null)
            TextButton(
              onPressed: () {
                setState(() {
                  _connectionStatusMessage = null; // Retour à l'état de liste
                });
                _setAndStartScan(widget.manager.bluetoothType); // Redémarrer le scan après l'échec
              },
              child: const Text('Retour à la liste'),
            )
        ],
      ),
    );
  }
  // --- FIN NOUVEL ÉTAT ---

  if (_discoveredDevices.isEmpty && _isScanning) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Recherche d\'appareils en cours...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  if (_discoveredDevices.isEmpty && !_isScanning) {
    return _buildEmptyState();
  }

  // Liste des appareils
  return ListView.builder(
    itemCount: _discoveredDevices.length,
    itemBuilder: (context, index) {
      final device = _discoveredDevices[index];
      // Assurez-vous que BluetoothDevice est importé si vous l'utilisez
      final isBle = device is BluetoothDevice && device.isBle; 

      final id = isBle ? device.id : device.address;

      final rawName = device.name as String?; 
      final name = rawName != null && rawName.isNotEmpty 
                    ? rawName 
                    : (isBle ? 'BLE Inconnu' : 'Classic Inconnu');
      
      // Vérifier si l'appareil actuel est l'appareil sélectionné (en cours de connexion)
      final bool isConnectingToThisDevice = _selectedDevice?.id == id;
      
      return ListTile(
        leading: Icon(
          isBle ? Icons.bluetooth_searching : Icons.bluetooth_connected,
          color: isBle ? Colors.lightBlue : Colors.blueGrey,
        ),
        title: Text(name),
        subtitle: Text('$id (${isBle ? "BLE" : "Classic"})'),
        
        // --- NOUVELLE ACTION TRAILING : Bouton "Connecter" ou Spinner ---
        trailing: isConnectingToThisDevice
          ? const SizedBox(
              width: 24, 
              height: 24, 
              child: CircularProgressIndicator(strokeWidth: 2)
            )
          : ElevatedButton(
              // Désactiver le bouton si le scan n'est pas terminé
              onPressed: _isScanning
                ? null 
                : () => _connectToSelectedDevice(device),
              child: const Text('Connecter'),
            ),
        // --- FIN NOUVELLE ACTION ---
        
        // Supprimer l'ancienne logique de connexion dans onTap pour la déplacer vers le bouton
        onTap: isConnectingToThisDevice 
          ? null // Désactiver le tap si la connexion est en cours
          : (_isScanning ? null : () => _connectToSelectedDevice(device)),
      );
    },
  );
}

/// État lorsque la liste est vide et le scan est terminé
Widget _buildEmptyState() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.bluetooth_disabled_outlined, size: 50, color: Colors.grey),
        const SizedBox(height: 10),
        const Text('Aucun appareil trouvé.', style: TextStyle(fontSize: 16)),
        TextButton(
          onPressed: () => _setAndStartScan(widget.manager.bluetoothType),
          child: const Text('Re-scanner'),
        )
      ],
    ),
  );
}

  /// État lorsque la liste est vide et le scan est terminé


  /// État d'erreur critique
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            const Text(
              'Erreur Critique Bluetooth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Ouvrir les paramètres Bluetooth'),
              onPressed: () {
                widget.manager.openBluetoothSettings();
                Navigator.pop(context);
              },
            ),
            TextButton(
              onPressed: () => _initializeAndScan(),
              child: const Text('Réessayer l\'initialisation'),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Hauteur ajustée pour un look modal propre
      height: MediaQuery.of(context).size.height * 0.75,
      width: MediaQuery.of(context).size.width * 0.85,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poignée et titre du modal
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 5),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sélecteur d\'Appareil Bluetooth',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          // En-tête (sélecteur Classic/BLE et progression)
          _buildHeader(),
          
          const Divider(height: 1),

          // Titre de la liste
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Text(
              'Appareils Découverts (${_discoveredDevices.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),

          // Corps (Liste des appareils ou État/Erreur)
          Expanded(
            child: _buildBody(),
          ),
          
          // Bouton pour fermer (en bas)
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: OutlinedButton(
              onPressed: () {
                widget.manager.stopScan();
                Navigator.pop(context);
              },
              child: const Text('Fermer'),
            ),
          ),
        ],
      ),
    );
  }
}