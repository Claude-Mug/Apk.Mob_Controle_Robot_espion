// control_settings_dialog.dart

import 'package:flutter/material.dart';
import 'dart:convert'; 
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lali_project/services/Services.Wifi.dart';
import 'package:lali_project/services/blue_manager.dart';

class ControlSettingsDialog extends StatefulWidget {
  final BluetoothManager bluetoothManager;
  final WiFiControlManager wifiManager;
  final Function(Map<String, String>) onCommandsUpdated;
  final Function(bool, bool) onPWMInversionUpdated;
  final Function(List<CustomControl>) onCustomControlsUpdated;

  const ControlSettingsDialog({
    Key? key,
    required this.bluetoothManager,
    required this.wifiManager,
    required this.onCommandsUpdated,
    required this.onPWMInversionUpdated,
    required this.onCustomControlsUpdated,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required BluetoothManager bluetoothManager,
    required WiFiControlManager wifiManager,
    required Function(Map<String, String>) onCommandsUpdated,
    required Function(bool, bool) onPWMInversionUpdated,
    required Function(List<CustomControl>) onCustomControlsUpdated,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => ControlSettingsDialog(
        bluetoothManager: bluetoothManager,
        wifiManager: wifiManager,
        onCommandsUpdated: onCommandsUpdated,
        onPWMInversionUpdated: onPWMInversionUpdated,
        onCustomControlsUpdated: onCustomControlsUpdated,
      ),
    );
  }

  @override
  State<ControlSettingsDialog> createState() => _ControlSettingsDialogState();
}

class CustomControl {
  final String id;
  String name;
  String commandOn;
  String commandOff;
  String icon;
  Color color;
  bool isActive;

  CustomControl({
    required this.id,
    required this.name,
    required this.commandOn,
    required this.commandOff,
    required this.icon,
    required this.color,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'commandOn': commandOn,
      'commandOff': commandOff,
      'icon': icon,
      'color': color.value,
      'isActive': isActive,
    };
  }

  factory CustomControl.fromMap(Map<String, dynamic> map) {
    return CustomControl(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? 'Nouveau Contrôle',
      commandOn: map['commandOn'] ?? 'CUSTOM:ON',
      commandOff: map['commandOff'] ?? 'CUSTOM:OFF',
      icon: map['icon'] ?? 'touch_app',
      color: Color(map['color'] ?? Colors.blue.value),
      isActive: map['isActive'] ?? true,
    );
  }
}

class _ControlSettingsDialogState extends State<ControlSettingsDialog> {
  // États des paramètres
  final Map<String, TextEditingController> _commandControllers = {};
  final Map<String, TextEditingController> _commandOffControllers = {};

  bool _isCommandsExpanded = false;
  
  bool _motor1Inverted = false;
  bool _motor2Inverted = false;
  
  // Paramètres PWM
  int _pwmMin = 0;
  int _pwmMax = 255;
  int _pwmSteps = 255;
  
  // Contrôles personnalisés
  final List<CustomControl> _customControls = [];
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customCommandOnController = TextEditingController();
  final TextEditingController _customCommandOffController = TextEditingController();
  String _selectedCustomIcon = 'touch_app';
  Color _selectedCustomColor = Colors.blue;
  
  // État de connexion
  String _connectionStatus = 'Non connecté';
  Color _connectionStatusColor = Colors.red;
  
  // Clés de stockage SharedPreferences
  static const String _commandsKey = 'control_commands';
  static const String _pwmInversionKey = 'pwm_inversion';
  static const String _pwmSettingsKey = 'pwm_settings';
  static const String _customControlsKey = 'custom_controls';

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadSettings();
    _updateConnectionStatus();
  }

 void _initializeControllers() {
  // Initialiser avec des valeurs vides d'abord
  final commandKeys = [
    'motor1', 'motor2', 'buzzer_on', 'buzzer_off', 'buzzer_pause',
    'direction_forward', 'direction_backward', 'direction_left', 'direction_right',
  ];

  for (var key in commandKeys) {
    _commandControllers[key] = TextEditingController(text: '');
    _commandOffControllers[key] = TextEditingController(text: '');
  }
}

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Charger les commandes
    final commandsJson = prefs.getString(_commandsKey);
    if (commandsJson != null) {
      try {
        final commandsMap = Map<String, dynamic>.from(json.decode(commandsJson));
        for (var entry in commandsMap.entries) {
          if (_commandControllers.containsKey(entry.key)) {
            _commandControllers[entry.key]!.text = entry.value;
          }
        }
      } catch (e) {
        print('Erreur chargement commandes: $e');
      }
    }

    // Charger l'inversion PWM
    final inversionJson = prefs.getString(_pwmInversionKey);
    if (inversionJson != null) {
      try {
        final inversionMap = Map<String, dynamic>.from(json.decode(inversionJson));
        setState(() {
          _motor1Inverted = inversionMap['motor1'] ?? false;
          _motor2Inverted = inversionMap['motor2'] ?? false;
        });
      } catch (e) {
        print('Erreur chargement inversion PWM: $e');
      }
    }

    // Charger paramètres PWM
    final pwmJson = prefs.getString(_pwmSettingsKey);
    if (pwmJson != null) {
      try {
        final pwmMap = Map<String, dynamic>.from(json.decode(pwmJson));
        setState(() {
          _pwmMin = pwmMap['min'] ?? 0;
          _pwmMax = pwmMap['max'] ?? 255;
          _pwmSteps = pwmMap['steps'] ?? 255;
        });
      } catch (e) {
        print('Erreur chargement paramètres PWM: $e');
      }
    }

    // Charger contrôles personnalisés
    final customJson = prefs.getString(_customControlsKey);
    if (customJson != null) {
      try {
        final customList = List<dynamic>.from(json.decode(customJson));
        setState(() {
          _customControls.clear();
          _customControls.addAll(
            customList.map((item) => CustomControl.fromMap(Map<String, dynamic>.from(item))),
          );
        });
      } catch (e) {
        print('Erreur chargement contrôles personnalisés: $e');
      }
    }

    setState(() {});
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Sauvegarder les commandes
    final commandsMap = <String, String>{};
    for (var entry in _commandControllers.entries) {
      commandsMap[entry.key] = entry.value.text;
    }
    prefs.setString(_commandsKey, json.encode(commandsMap));

    // Sauvegarder l'inversion PWM
    prefs.setString(_pwmInversionKey, json.encode({
      'motor1': _motor1Inverted,
      'motor2': _motor2Inverted,
    }));

    // Sauvegarder paramètres PWM
    prefs.setString(_pwmSettingsKey, json.encode({
      'min': _pwmMin,
      'max': _pwmMax,
      'steps': _pwmSteps,
    }));

    // Sauvegarder contrôles personnalisés
    prefs.setString(_customControlsKey, json.encode(
      _customControls.map((control) => control.toMap()).toList(),
    ));

    // Notifier les callbacks
    widget.onCommandsUpdated(commandsMap);
    widget.onPWMInversionUpdated(_motor1Inverted, _motor2Inverted);
    widget.onCustomControlsUpdated(_customControls);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Paramètres sauvegardés avec succès'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _updateConnectionStatus() {
    bool isConnected = false;
    String status = 'Non connecté';
    Color color = Colors.red;

    if (widget.wifiManager.hasActiveConnection) {
      isConnected = true;
      status = 'WiFi Connecté';
      color = Colors.green;
    } else if (widget.bluetoothManager.connectedDevice != null) {
      isConnected = true;
      status = 'Bluetooth Connecté';
      color = Colors.blue;
    }

    setState(() {
      _connectionStatus = status;
      _connectionStatusColor = color;
    });
  }

  void _showEditCommandModal(String commandId, String commandName) {
  // Récupérer les valeurs existantes AVANT d'ouvrir le modal
  final existingOnCommand = _commandControllers[commandId]?.text ?? '';
  final existingOffCommand = _commandOffControllers[commandId]?.text ?? '';
  
  showDialog(
    context: context,
    builder: (context) => _buildCommandEditDialog(
      commandId, 
      commandName, 
      existingOnCommand, 
      existingOffCommand
    ),
  );
}

  Widget _buildCommandEditDialog(
  String commandId, 
  String commandName, 
  String existingOnCommand,
  String existingOffCommand
) {
  // Créer des contrôleurs temporaires avec les valeurs existantes
  final onController = TextEditingController(text: existingOnCommand);
  final offController = TextEditingController(text: existingOffCommand);
  
  final hasOffCommand = existingOffCommand.isNotEmpty;

  return Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              const Icon(Icons.edit, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              Text(
                'Modifier $commandName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Champ commande ON
          TextField(
            controller: onController,
            decoration: const InputDecoration(
              labelText: 'Commande ON',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.play_arrow, color: Colors.green),
              hintText: 'Ex: MOTOR:M1:PWM:',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // Champ commande OFF (si applicable)
          if (hasOffCommand) ...[
            TextField(
              controller: offController,
              decoration: const InputDecoration(
                labelText: 'Commande OFF',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.stop, color: Colors.red),
                hintText: 'Ex: MOTOR:M1:STOP',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
          ],

          // Boutons d'action
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // NE PAS DISPOSER LES CONTRÔLEURS ICI - ils seront nettoyés automatiquement
                  },
                  child: const Text('ANNULER'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Mettre à jour les contrôleurs principaux avec les nouvelles valeurs
                    _commandControllers[commandId]!.text = onController.text;
                    if (hasOffCommand) {
                      _commandOffControllers[commandId]!.text = offController.text;
                    }
                    
                    setState(() {});
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Commande $commandName mise à jour'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    
                    // NE PAS DISPOSER LES CONTRÔLEURS ICI - ils seront nettoyés automatiquement
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('SAUVEGARDER'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  void _showCustomControlModal({CustomControl? existingControl}) {
    final isEditing = existingControl != null;
    
    if (isEditing) {
      _customNameController.text = existingControl!.name;
      _customCommandOnController.text = existingControl.commandOn;
      _customCommandOffController.text = existingControl.commandOff;
      _selectedCustomIcon = existingControl.icon;
      _selectedCustomColor = existingControl.color;
    } else {
      _customNameController.clear();
      _customCommandOnController.clear();
      _customCommandOffController.clear();
      _selectedCustomIcon = 'touch_app';
      _selectedCustomColor = Colors.blue;
    }

    showDialog(
      context: context,
      builder: (context) => _buildCustomControlDialog(isEditing, existingControl),
    ).then((_) {
      if (!isEditing) {
        _customNameController.clear();
        _customCommandOnController.clear();
        _customCommandOffController.clear();
      }
    });
  }

  Widget _buildCustomControlDialog(bool isEditing, CustomControl? existingControl) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Icon(Icons.add_circle, color: Colors.purple, size: 24),
                const SizedBox(width: 12),
                Text(
                  isEditing ? 'Modifier le contrôle' : 'Nouveau contrôle',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Nom du contrôle
            TextField(
              controller: _customNameController,
              decoration: const InputDecoration(
                labelText: 'Nom du contrôle',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
            ),
            const SizedBox(height: 16),

            // Commande ON
            TextField(
              controller: _customCommandOnController,
              decoration: const InputDecoration(
                labelText: 'Commande ON',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.play_arrow, color: Colors.green),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Commande OFF
            TextField(
              controller: _customCommandOffController,
              decoration: const InputDecoration(
                labelText: 'Commande OFF',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.stop, color: Colors.red),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Sélection icône et couleur
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showIconSelector,
                    icon: Icon(_getIconData(_selectedCustomIcon)),
                    label: const Text('Icône'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showColorSelector,
                    icon: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _selectedCustomColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: const Text('Couleur'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Boutons d'action
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ANNULER'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_customNameController.text.isEmpty || 
                          _customCommandOnController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Veuillez remplir le nom et la commande ON'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final control = CustomControl(
                        id: existingControl?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                        name: _customNameController.text,
                        commandOn: _customCommandOnController.text,
                        commandOff: _customCommandOffController.text,
                        icon: _selectedCustomIcon,
                        color: _selectedCustomColor,
                      );

                      setState(() {
                        if (isEditing) {
                          final index = _customControls.indexWhere((c) => c.id == existingControl!.id);
                          if (index != -1) {
                            _customControls[index] = control;
                          }
                        } else {
                          _customControls.add(control);
                        }
                      });

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Contrôle ${isEditing ? 'modifié' : 'ajouté'} avec succès'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(isEditing ? 'MODIFIER' : 'AJOUTER'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showIconSelector() {
    final icons = [
      'touch_app', 'play_arrow', 'stop', 'pause', 'power_settings_new',
      'settings', 'build', 'tune', 'speed', 'flash_on', 'highlight',
      'bolt', 'ac_unit', 'whatshot', 'gamepad', 'joystick', 'sports_esports'
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sélectionner une icône'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: icons.length,
            itemBuilder: (context, index) => IconButton(
              icon: Icon(
                _getIconData(icons[index]),
                color: _selectedCustomIcon == icons[index] 
                    ? _selectedCustomColor 
                    : Colors.grey[600],
                size: 28,
              ),
              onPressed: () {
                setState(() {
                  _selectedCustomIcon = icons[index];
                });
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showColorSelector() {
    final colors = [
      Colors.red, Colors.green, Colors.blue, Colors.orange,
      Colors.purple, Colors.teal, Colors.indigo, Colors.amber,
      Colors.pink, Colors.cyan, Colors.lime, Colors.brown,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sélectionner une couleur'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: colors.length,
            itemBuilder: (context, index) => GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCustomColor = colors[index];
                });
                Navigator.pop(context);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: colors[index],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selectedCustomColor == colors[index] 
                        ? Colors.black 
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconData(String iconName) {
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
      case 'joystick': return Icons.live_tv;
      case 'sports_esports': return Icons.sports_esports;
      default: return Icons.touch_app;
    }
  }

  void _deleteCustomControl(String controlId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le contrôle'),
        content: const Text('Êtes-vous sûr de vouloir supprimer ce contrôle ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _customControls.removeWhere((control) => control.id == controlId);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Contrôle supprimé'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SUPPRIMER', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleCustomControl(String controlId) {
    setState(() {
      final control = _customControls.firstWhere((c) => c.id == controlId);
      control.isActive = !control.isActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // En-tête
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue[800],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.settings, color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'PARAMÈTRES DE CONTRÔLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Statut de connexion
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _connectionStatusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: _connectionStatusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: _connectionStatusColor,
                          size: 12,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _connectionStatus,
                          style: TextStyle(
                            color: _connectionStatusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Contenu défilable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

// NOUVELLE SECTION : Commandes Avancées (Utilise ExpansionTile)
                 ExpansionTile(
                 initiallyExpanded: _isCommandsExpanded, // L'état actuel de la section
                 onExpansionChanged: (expanded) {
                 setState(() {
                _isCommandsExpanded = expanded;
              });
            },
  // Le titre de la section
           title: Row(
            children: [
            Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_button, color: Colors.blue, size: 20),
           ),
            const SizedBox(width: 12),
            const Text(
           'Commandes Avancées', // Nouveau nom plus pro
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    ],
  ),
  // Le sous-titre pour indiquer que c'est modifiable
  subtitle: Text(
    _isCommandsExpanded
        ? 'Cliquez pour fermer'
        : 'Cliquez pour modifier les commandes ON/OFF par défaut',
    style: TextStyle(color: Colors.blueGrey[600]),
  ),
  // Le contenu (la grille des commandes)
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: _buildCommandGrid(),
    ),
  ],
),

const SizedBox(height: 24), // Conserver cette SizedBox pour l'espacement


                    // Section Configuration PWM
                    _buildSectionTitle(
                      'Configuration PWM',
                      Icons.speed,
                      Colors.orange,
                    ),
                    _buildPWMConfiguration(),

                    const SizedBox(height: 24),

                    // Section Contrôles Personnalisés
                    _buildSectionTitle(
                      'Contrôles Personnalisés',
                      Icons.gamepad,
                      Colors.purple,
                    ),
                    _buildCustomControlsSection(),
                  ],
                ),
              ),
            ),

            // Boutons d'action
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _saveSettings(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('RÉINITIALISER'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _saveSettings();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('SAUVEGARDER'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandGrid() {
    final commandGroups = {
      'Moteurs (Ex: PWM)': ['motor1', 'motor2'], // Renommer pour donner un indice
      'Buzzer (ON/OFF/PAUSE)': ['buzzer_on', 'buzzer_off', 'buzzer_pause'],
      'Directions (Avancer/Reculer)': ['direction_forward', 'direction_backward', 'direction_left', 'direction_right'],
    };

    final commandLabels = {
      'motor1': 'Moteur 1',
      'motor2': 'Moteur 2',
      'buzzer_on': 'Buzzer ON',
      'buzzer_off': 'Buzzer OFF',
      'buzzer_pause': 'Buzzer PAUSE',
      'direction_forward': 'Direction Avant',
      'direction_backward': 'Direction Arrière',
      'direction_left': 'Direction Gauche',
      'direction_right': 'Direction Droite',
    };

    return Column(
      children: commandGroups.entries.map((group) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre du groupe
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                group.key,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey, // Changer la couleur pour plus de contraste
                  fontSize: 16,
                ),
              ),
            ),
            
            // Liste des commandes dans ce groupe
            ...group.value.map((commandId) {
              return _buildCommandCard(
                commandLabels[commandId]!,
                _commandControllers[commandId]!.text,
                () => _showEditCommandModal(commandId, commandLabels[commandId]!),
              );
            }).toList(),

            const SizedBox(height: 12),
          ],
        );
      }).toList(),
    );
  }

 Widget _buildCommandCard(String title, String command, VoidCallback onEdit) {
    return Card(
      elevation: 0, // Moins d'ombre, plus plat
      margin: const EdgeInsets.symmetric(vertical: 4), // Marge verticale réduite
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1), // Ajout d'une bordure claire
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0), // Padding réduit
        leading: const Icon(Icons.code, color: Colors.blue, size: 24),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          // Afficher la commande complète ou tronquée
          command,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 18),
          onPressed: onEdit,
          color: Colors.blue,
        ),
        onTap: onEdit, // Rendre la carte cliquable pour modifier
      ),
    );
  }

  Widget _buildPWMConfiguration() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Inversion PWM (MODIFIÉ: Affichage en colonne)
            // Ligne 1 : Inverser Moteur 1
            _buildInversionToggle(
              'Inverser Moteur 1',
              _motor1Inverted,
              (value) => setState(() => _motor1Inverted = value),
            ),
            const SizedBox(height: 12), // Ajout d'un espace vertical
            // Ligne 2 : Inverser Moteur 2
            _buildInversionToggle(
              'Inverser Moteur 2',
              _motor2Inverted,
              (value) => setState(() => _motor2Inverted = value),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            
            // Paramètres PWM avancés (Le reste reste inchangé)
            const Text(
              'Paramètres PWM Avancés',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            _buildPWMSlider('PWM Min', _pwmMin, 0, 255, (value) {
              setState(() => _pwmMin = value.toInt());
            }),
            _buildPWMSlider('PWM Max', _pwmMax, 0, 255, (value) {
              setState(() => _pwmMax = value.toInt());
            }),
            _buildPWMSlider('Pas PWM', _pwmSteps, 1, 255, (value) {
              setState(() => _pwmSteps = value.toInt());
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInversionToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Card(
      elevation: 1,
      color: Colors.grey[50],
      child: SwitchListTile(
        title: Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        value: value,
        onChanged: onChanged,
        secondary: Icon(
          value ? Icons.swap_horiz : Icons.swap_vert,
          color: value ? Colors.orange : Colors.grey,
        ),
        activeColor: Colors.orange,
      ),
    );
  }

  Widget _buildPWMSlider(String label, int value, int min, int max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: onChanged,
          activeColor: Colors.orange,
          inactiveColor: Colors.orange.withOpacity(0.3),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCustomControlsSection() {
    return Column(
      children: [
        // Bouton ajouter
        Card(
          elevation: 2,
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.purple),
            ),
            title: const Text(
              'Ajouter un contrôle personnalisé',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Créer un nouveau bouton de contrôle'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showCustomControlModal(),
          ),
        ),
        const SizedBox(height: 16),

        // Liste des contrôles personnalisés
        if (_customControls.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.gamepad, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucun contrôle personnalisé',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ..._customControls.map((control) => _buildCustomControlCard(control)),
      ],
    );
  }

  Widget _buildCustomControlCard(CustomControl control) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: control.color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getIconData(control.icon),
            color: control.color,
          ),
        ),
        title: Text(
          control.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: control.isActive ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ON: ${control.commandOn}',
              style: TextStyle(
                fontSize: 10,
                color: control.isActive ? Colors.green : Colors.grey,
              ),
            ),
            if (control.commandOff.isNotEmpty)
              Text(
                'OFF: ${control.commandOff}',
                style: TextStyle(
                  fontSize: 10,
                  color: control.isActive ? Colors.red : Colors.grey,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                control.isActive ? Icons.toggle_on : Icons.toggle_off,
                color: control.isActive ? Colors.green : Colors.grey,
                size: 30,
              ),
              onPressed: () => _toggleCustomControl(control.id),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showCustomControlModal(existingControl: control),
              color: Colors.blue,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              onPressed: () => _deleteCustomControl(control.id),
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _commandControllers.values) {
      controller.dispose();
    }
    for (var controller in _commandOffControllers.values) {
      controller.dispose();
    }
    _customNameController.dispose();
    _customCommandOnController.dispose();
    _customCommandOffController.dispose();
    super.dispose();
  }
}