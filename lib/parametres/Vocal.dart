 // vocal_settings.dart - Paramètres de normalisation vocale

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VocalSettingsModal extends StatefulWidget {
  final Function(VocalNormalizationSettings) onSettingsChanged;

  const VocalSettingsModal({
    Key? key,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<VocalSettingsModal> createState() => _VocalSettingsModalState();
}

class _VocalSettingsModalState extends State<VocalSettingsModal> {
  late VocalNormalizationSettings _settings;
  final TextEditingController _prefixController = TextEditingController();
  final TextEditingController _suffixController = TextEditingController();
  final TextEditingController _customReplacementController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await VocalNormalizationSettings.loadFromPrefs();
    setState(() {
      _settings = settings;
      _prefixController.text = settings.prefix;
      _suffixController.text = settings.suffix;
    });
  }

  Future<void> _saveSettings() async {
    await _settings.saveToPrefs();
    widget.onSettingsChanged(_settings);
    _showSuccess('Paramètres sauvegardés');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetToDefaults() {
    setState(() {
      _settings = VocalNormalizationSettings.defaultSettings();
      _prefixController.text = _settings.prefix;
      _suffixController.text = _settings.suffix;
    });
    _showSuccess('Paramètres réinitialisés');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Paramètres Vocaux',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.green),
            onPressed: _saveSettings,
            tooltip: 'Sauvegarder',
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.orange),
            onPressed: _resetToDefaults,
            tooltip: 'Réinitialiser',
          ),
        ],
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Transformation du Texte'),
                  _buildCaseTransformation(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Gestion des Espaces'),
                  _buildSpaceManagement(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Nettoyage du Texte'),
                  _buildTextCleaning(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Préfixe et Suffixe'),
                  _buildPrefixSuffix(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Paramètres Avancés'),
                  _buildAdvancedSettings(),
                  const SizedBox(height: 32),
                  
                  _buildPreviewSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildCaseTransformation() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transformation de la casse',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...TextTransformation.values.map((transformation) {
              return RadioListTile<TextTransformation>(
                title: Text(_getTransformationLabel(transformation)),
                value: transformation,
                groupValue: _settings.textTransformation,
                onChanged: (value) {
                  setState(() {
                    _settings.textTransformation = value!;
                  });
                },
                dense: true,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceManagement() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gestion des espaces',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...SpaceReplacement.values.map((replacement) {
              return RadioListTile<SpaceReplacement>(
                title: Text(_getSpaceReplacementLabel(replacement)),
                value: replacement,
                groupValue: _settings.spaceReplacement,
                onChanged: (value) {
                  setState(() {
                    _settings.spaceReplacement = value!;
                  });
                },
                dense: true,
              );
            }).toList(),
            const SizedBox(height: 12),
            TextField(
              controller: _customReplacementController,
              decoration: const InputDecoration(
                labelText: 'Caractère personnalisé',
                hintText: 'Ex: -, _, ., ~',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _settings.customSpaceReplacement = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextCleaning() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nettoyage du texte',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Supprimer les accents'),
              value: _settings.removeAccents,
              onChanged: (value) {
                setState(() {
                  _settings.removeAccents = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Supprimer la ponctuation'),
              value: _settings.removePunctuation,
              onChanged: (value) {
                setState(() {
                  _settings.removePunctuation = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Supprimer les caractères spéciaux'),
              value: _settings.removeSpecialChars,
              onChanged: (value) {
                setState(() {
                  _settings.removeSpecialChars = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Supprimer les espaces multiples'),
              value: _settings.removeMultipleSpaces,
              onChanged: (value) {
                setState(() {
                  _settings.removeMultipleSpaces = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Supprimer les espaces en début/fin'),
              value: _settings.trimSpaces,
              onChanged: (value) {
                setState(() {
                  _settings.trimSpaces = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrefixSuffix() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Préfixe et Suffixe',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefixController,
              decoration: const InputDecoration(
                labelText: 'Préfixe',
                hintText: 'Ex: CMD_, VOICE_, #',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _settings.prefix = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _suffixController,
              decoration: const InputDecoration(
                labelText: 'Suffixe',
                hintText: 'Ex: _END, !, .',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _settings.suffix = value;
                });
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Ajouter automatiquement un séparateur'),
              subtitle: const Text('Ajoute un espace/tiret après le préfixe et avant le suffixe'),
              value: _settings.autoAddSeparator,
              onChanged: (value) {
                setState(() {
                  _settings.autoAddSeparator = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paramètres avancés',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Activer la normalisation vocale'),
              subtitle: const Text('Appliquer automatiquement les transformations'),
              value: _settings.enableNormalization,
              onChanged: (value) {
                setState(() {
                  _settings.enableNormalization = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Mode débug'),
              subtitle: const Text('Afficher les étapes de transformation dans la console'),
              value: _settings.debugMode,
              onChanged: (value) {
                setState(() {
                  _settings.debugMode = value;
                });
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Longueur maximale du texte'),
              subtitle: Slider(
                value: _settings.maxTextLength.toDouble(),
                min: 10,
                max: 500,
                divisions: 49,
                label: '${_settings.maxTextLength} caractères',
                onChanged: (value) {
                  setState(() {
                    _settings.maxTextLength = value.toInt();
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    const testText = 'Écoute-moi parler avec des ACCENTS et de la ponctuation!';
    final normalizedText = _settings.normalizeText(testText);

    return Card(
      elevation: 3,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aperçu en temps réel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            _buildPreviewItem('Texte original:', testText),
            const SizedBox(height: 12),
            _buildPreviewItem('Texte normalisé:', normalizedText),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette prévisualisation montre comment votre texte sera transformé',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontSize: 12,
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

  Widget _buildPreviewItem(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'Monospace',
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  String _getTransformationLabel(TextTransformation transformation) {
    switch (transformation) {
      case TextTransformation.uppercase:
        return 'MAJUSCULES';
      case TextTransformation.lowercase:
        return 'minuscules';
      case TextTransformation.capitalize:
        return 'Première Lettre Majuscule';
      case TextTransformation.titleCase:
        return 'Format Titre';
      case TextTransformation.none:
        return 'Aucune transformation';
    }
  }

  String _getSpaceReplacementLabel(SpaceReplacement replacement) {
    switch (replacement) {
      case SpaceReplacement.none:
        return 'Aucun espace';
      case SpaceReplacement.space:
        return 'Espaces normaux';
      case SpaceReplacement.underscore:
        return 'Tiret bas (_)';
      case SpaceReplacement.dash:
        return 'Tiret (-)';
      case SpaceReplacement.dot:
        return 'Point (.)';
      case SpaceReplacement.custom:
        return 'Personnalisé';
    }
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    _customReplacementController.dispose();
    super.dispose();
  }
}

// Enumérations pour les types de transformation
enum TextTransformation {
  uppercase,
  lowercase,
  capitalize,
  titleCase,
  none,
}

enum SpaceReplacement {
  none,
  space,
  underscore,
  dash,
  dot,
  custom,
}

// Classe principale des paramètres
class VocalNormalizationSettings {
  TextTransformation textTransformation;
  SpaceReplacement spaceReplacement;
  String customSpaceReplacement;
  bool removeAccents;
  bool removePunctuation;
  bool removeSpecialChars;
  bool removeMultipleSpaces;
  bool trimSpaces;
  String prefix;
  String suffix;
  bool autoAddSeparator;
  bool enableNormalization;
  bool debugMode;
  int maxTextLength;

  VocalNormalizationSettings({
    required this.textTransformation,
    required this.spaceReplacement,
    required this.customSpaceReplacement,
    required this.removeAccents,
    required this.removePunctuation,
    required this.removeSpecialChars,
    required this.removeMultipleSpaces,
    required this.trimSpaces,
    required this.prefix,
    required this.suffix,
    required this.autoAddSeparator,
    required this.enableNormalization,
    required this.debugMode,
    required this.maxTextLength,
  });

  // Paramètres par défaut
  factory VocalNormalizationSettings.defaultSettings() {
    return VocalNormalizationSettings(
      textTransformation: TextTransformation.uppercase,
      spaceReplacement: SpaceReplacement.space,
      customSpaceReplacement: '_',
      removeAccents: true,
      removePunctuation: true,
      removeSpecialChars: true,
      removeMultipleSpaces: true,
      trimSpaces: true,
      prefix: '',
      suffix: '',
      autoAddSeparator: true,
      enableNormalization: true,
      debugMode: false,
      maxTextLength: 100,
    );
  }

  // Charger depuis SharedPreferences
  static Future<VocalNormalizationSettings> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    return VocalNormalizationSettings(
      textTransformation: TextTransformation.values[
          prefs.getInt('textTransformation') ?? TextTransformation.uppercase.index],
      spaceReplacement: SpaceReplacement.values[
          prefs.getInt('spaceReplacement') ?? SpaceReplacement.space.index],
      customSpaceReplacement: prefs.getString('customSpaceReplacement') ?? '_',
      removeAccents: prefs.getBool('removeAccents') ?? true,
      removePunctuation: prefs.getBool('removePunctuation') ?? true,
      removeSpecialChars: prefs.getBool('removeSpecialChars') ?? true,
      removeMultipleSpaces: prefs.getBool('removeMultipleSpaces') ?? true,
      trimSpaces: prefs.getBool('trimSpaces') ?? true,
      prefix: prefs.getString('prefix') ?? '',
      suffix: prefs.getString('suffix') ?? '',
      autoAddSeparator: prefs.getBool('autoAddSeparator') ?? true,
      enableNormalization: prefs.getBool('enableNormalization') ?? true,
      debugMode: prefs.getBool('debugMode') ?? false,
      maxTextLength: prefs.getInt('maxTextLength') ?? 100,
    );
  }

  // Sauvegarder dans SharedPreferences
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setInt('textTransformation', textTransformation.index);
    await prefs.setInt('spaceReplacement', spaceReplacement.index);
    await prefs.setString('customSpaceReplacement', customSpaceReplacement);
    await prefs.setBool('removeAccents', removeAccents);
    await prefs.setBool('removePunctuation', removePunctuation);
    await prefs.setBool('removeSpecialChars', removeSpecialChars);
    await prefs.setBool('removeMultipleSpaces', removeMultipleSpaces);
    await prefs.setBool('trimSpaces', trimSpaces);
    await prefs.setString('prefix', prefix);
    await prefs.setString('suffix', suffix);
    await prefs.setBool('autoAddSeparator', autoAddSeparator);
    await prefs.setBool('enableNormalization', enableNormalization);
    await prefs.setBool('debugMode', debugMode);
    await prefs.setInt('maxTextLength', maxTextLength);
  }

  // Méthode de normalisation principale
  String normalizeText(String text) {
    if (!enableNormalization) return text;

    String normalized = text;

    // Étape 1: Supprimer les accents
    if (removeAccents) {
      normalized = _removeAccents(normalized);
    }

    // Étape 2: Supprimer la ponctuation
    if (removePunctuation) {
      normalized = _removePunctuation(normalized);
    }

    // Étape 3: Supprimer les caractères spéciaux
    if (removeSpecialChars) {
      normalized = _removeSpecialChars(normalized);
    }

    // Étape 4: Gérer les espaces
    normalized = _manageSpaces(normalized);

    // Étape 5: Appliquer la transformation de casse
    normalized = _applyCaseTransformation(normalized);

    // Étape 6: Tronquer si nécessaire
    if (normalized.length > maxTextLength) {
      normalized = normalized.substring(0, maxTextLength);
    }

    // Étape 7: Ajouter préfixe et suffixe
    normalized = _addPrefixSuffix(normalized);

    return normalized;
  }

  String _removeAccents(String text) {
    return text
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[ÀÁÂÃÄÅ]'), 'A')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ÈÉÊË]'), 'E')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[ÌÍÎÏ]'), 'I')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ÒÓÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ÙÚÛÜ]'), 'U')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[Ç]'), 'C')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[Ñ]'), 'N');
  }

  String _removePunctuation(String text) {
    return text.replaceAll(RegExp(r'[^\w\s]'), '');
  }

  String _removeSpecialChars(String text) {
    return text.replaceAll(RegExp(r'[^\w\s]'), '');
  }

  String _manageSpaces(String text) {
    String result = text;

    // Supprimer les espaces multiples
    if (removeMultipleSpaces) {
      result = result.replaceAll(RegExp(r'\s+'), ' ');
    }

    // Supprimer les espaces en début/fin
    if (trimSpaces) {
      result = result.trim();
    }

    // Remplacer les espaces selon le mode choisi
    switch (spaceReplacement) {
      case SpaceReplacement.none:
        result = result.replaceAll(RegExp(r'\s+'), '');
        break;
      case SpaceReplacement.space:
        // Garder les espaces normaux
        break;
      case SpaceReplacement.underscore:
        result = result.replaceAll(RegExp(r'\s+'), '_');
        break;
      case SpaceReplacement.dash:
        result = result.replaceAll(RegExp(r'\s+'), '-');
        break;
      case SpaceReplacement.dot:
        result = result.replaceAll(RegExp(r'\s+'), '.');
        break;
      case SpaceReplacement.custom:
        result = result.replaceAll(RegExp(r'\s+'), customSpaceReplacement);
        break;
    }

    return result;
  }

  String _applyCaseTransformation(String text) {
    switch (textTransformation) {
      case TextTransformation.uppercase:
        return text.toUpperCase();
      case TextTransformation.lowercase:
        return text.toLowerCase();
      case TextTransformation.capitalize:
        if (text.isEmpty) return text;
        return text[0].toUpperCase() + text.substring(1).toLowerCase();
      case TextTransformation.titleCase:
        return text
            .toLowerCase()
            .split(' ')
            .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
            .join(' ');
      case TextTransformation.none:
        return text;
    }
  }

  String _addPrefixSuffix(String text) {
    String result = text;

    if (prefix.isNotEmpty) {
      if (autoAddSeparator) {
        result = '$prefix${_getSeparator()}$result';
      } else {
        result = '$prefix$result';
      }
    }

    if (suffix.isNotEmpty) {
      if (autoAddSeparator) {
        result = '$result${_getSeparator()}$suffix';
      } else {
        result = '$result$suffix';
      }
    }

    return result;
  }

  String _getSeparator() {
    switch (spaceReplacement) {
      case SpaceReplacement.none:
        return '';
      case SpaceReplacement.space:
        return ' ';
      case SpaceReplacement.underscore:
        return '_';
      case SpaceReplacement.dash:
        return '-';
      case SpaceReplacement.dot:
        return '.';
      case SpaceReplacement.custom:
        return customSpaceReplacement;
    }
  }

  // Méthode pour afficher les paramètres (debug)
  Map<String, dynamic> toMap() {
    return {
      'textTransformation': textTransformation.toString(),
      'spaceReplacement': spaceReplacement.toString(),
      'customSpaceReplacement': customSpaceReplacement,
      'removeAccents': removeAccents,
      'removePunctuation': removePunctuation,
      'removeSpecialChars': removeSpecialChars,
      'removeMultipleSpaces': removeMultipleSpaces,
      'trimSpaces': trimSpaces,
      'prefix': prefix,
      'suffix': suffix,
      'autoAddSeparator': autoAddSeparator,
      'enableNormalization': enableNormalization,
      'debugMode': debugMode,
      'maxTextLength': maxTextLength,
    };
  }
}

// Méthode utilitaire pour ouvrir le modal
 // vocal_settings.dart (à la fin du fichier)

// Méthode utilitaire pour ouvrir le modal
class VocalSettings {
  static Future<void> showModal({
    required BuildContext context,
    required Function(VocalNormalizationSettings) onSettingsChanged,
  }) async {
    // 1. Utilisez showDialog pour un dialogue personnalisé
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // 2. Calculez les dimensions (75% de l'écran)
        final Size screenSize = MediaQuery.of(dialogContext).size;
        final double dialogWidth = screenSize.width * 0.85;
        final double dialogHeight = screenSize.height * 0.85;

        // 3. Utilisez Center et SizedBox pour définir la taille
        return Center(
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            // 4. Mettez le VocalSettingsModal dans un Material pour le style de dialogue
            child: Material(
              // Optionnel: pour des bords arrondis
              borderRadius: BorderRadius.circular(15.0),
              clipBehavior: Clip.antiAlias,
              child: VocalSettingsModal(
                onSettingsChanged: onSettingsChanged,
              ),
            ),
          ),
        );
      },
      // Optionnel: permet de fermer en tapant en dehors
      barrierDismissible: true,
    );
  }
}