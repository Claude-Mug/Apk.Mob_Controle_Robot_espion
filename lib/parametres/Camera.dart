// parametres/Camera.dart
import 'package:flutter/material.dart';
import 'package:lali_project/page/camera_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraSettings extends StatefulWidget {
  const CameraSettings({Key? key}) : super(key: key);

  @override
  State<CameraSettings> createState() => _CameraSettingsState();
}

class _CameraSettingsState extends State<CameraSettings> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Paramètres Caméra
  String _selectedResolution = '1920x1080';
  String _selectedQuality = 'Haute';
  String _whiteBalance = 'Auto';
  double _exposureValue = 0.0;
  bool _flashEnabled = false;
  bool _autoFocus = true;
  bool _hdrEnabled = false;
  double _zoomLevel = 1.0;
  String _videoFormat = 'MP4';
  
  // Paramètres Serveur
  String _serverIP = '10.67.239.152';
  int _serverPort = 8080;
  bool _autoStartServer = true;
  bool _enableBroadcast = true;
  String _streamQuality = 'HD';
  int _maxConnections = 5;
  bool _enableAuthentication = false;
  String _storagePath = '/storage/emulated/0/CameraServer/';
  
  // Paramètres Client
  String _clientIP = '10.67.239.152';
  int _clientPort = 8080;
  bool _autoConnect = true;
  bool _showPreview = true;
  String _previewQuality = 'Medium';
  bool _saveToGallery = true;
  bool _notificationsEnabled = true;
  
  // Liste des options
  final List<String> _resolutions = ['640x480', '1280x720', '1920x1080', '3840x2160'];
  final List<String> _qualities = ['Basse', 'Moyenne', 'Haute', 'Très haute'];
  final List<String> _whiteBalances = ['Auto', 'Soleil', 'Nuage', 'Tungstène', 'Fluorescent'];
  final List<String> _videoFormats = ['MP4', 'AVI', 'MOV', 'MKV'];
  final List<String> _streamQualities = ['SD', 'HD', 'Full HD', '4K'];
  final List<String> _previewQualities = ['Low', 'Medium', 'High'];
  

  // Clés pour SharedPreferences
  static const String _resolutionKey = 'camera_resolution';
  static const String _qualityKey = 'camera_quality';
  static const String _whiteBalanceKey = 'camera_white_balance';
  static const String _exposureKey = 'camera_exposure';
  static const String _flashKey = 'camera_flash';
  static const String _autoFocusKey = 'camera_auto_focus';
  static const String _hdrKey = 'camera_hdr';
  static const String _zoomKey = 'camera_zoom';
  static const String _videoFormatKey = 'camera_video_format';
  
  static const String _serverIpKey = 'server_ip';
  static const String _serverPortKey = 'server_port';
  static const String _autoStartKey = 'server_auto_start';
  static const String _broadcastKey = 'server_broadcast';
  static const String _streamQualityKey = 'server_stream_quality';
  static const String _maxConnectionsKey = 'server_max_connections';
  static const String _authKey = 'server_authentication';
  static const String _storagePathKey = 'server_storage_path';
  
  static const String _clientIpKey = 'client_ip';
  static const String _clientPortKey = 'client_port';
  static const String _autoConnectKey = 'client_auto_connect';
  static const String _showPreviewKey = 'client_show_preview';
  static const String _previewQualityKey = 'client_preview_quality';
  static const String _saveGalleryKey = 'client_save_gallery';
  static const String _notificationsKey = 'client_notifications';

  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initPreferences();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // 1. Charger les valeurs
    final ip = await CameraSettingsManager.getServerIP();
    final port = await CameraSettingsManager.getServerPort();

    // 2. Mettre à jour l'état du widget pour que l'UI se rafraîchisse
    setState(() {
      _serverIP = ip;
      _serverPort = port;
      // Charger les autres paramètres (résolution, qualité, etc.) de la même manière
    });
  }

  Future<void> _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    setState(() {
      // Paramètres Caméra
      _selectedResolution = _prefs.getString(_resolutionKey) ?? '1920x1080';
      _selectedQuality = _prefs.getString(_qualityKey) ?? 'Haute';
      _whiteBalance = _prefs.getString(_whiteBalanceKey) ?? 'Auto';
      _exposureValue = _prefs.getDouble(_exposureKey) ?? 0.0;
      _flashEnabled = _prefs.getBool(_flashKey) ?? false;
      _autoFocus = _prefs.getBool(_autoFocusKey) ?? true;
      _hdrEnabled = _prefs.getBool(_hdrKey) ?? false;
      _zoomLevel = _prefs.getDouble(_zoomKey) ?? 1.0;
      _videoFormat = _prefs.getString(_videoFormatKey) ?? 'MP4';
      
      // Paramètres Serveur
      _serverIP = _prefs.getString(_serverIpKey) ?? '10.67.239.152';
      _serverPort = _prefs.getInt(_serverPortKey) ?? 8080;
      _autoStartServer = _prefs.getBool(_autoStartKey) ?? true;
      _enableBroadcast = _prefs.getBool(_broadcastKey) ?? true;
      _streamQuality = _prefs.getString(_streamQualityKey) ?? 'HD';
      _maxConnections = _prefs.getInt(_maxConnectionsKey) ?? 5;
      _enableAuthentication = _prefs.getBool(_authKey) ?? false;
      _storagePath = _prefs.getString(_storagePathKey) ?? '/storage/emulated/0/CameraServer/';
      
      // Paramètres Client
      _clientIP = _prefs.getString(_clientIpKey) ?? '10.67.239.152';
      _clientPort = _prefs.getInt(_clientPortKey) ?? 8080;
      _autoConnect = _prefs.getBool(_autoConnectKey) ?? true;
      _showPreview = _prefs.getBool(_showPreviewKey) ?? true;
      _previewQuality = _prefs.getString(_previewQualityKey) ?? 'Medium';
      _saveToGallery = _prefs.getBool(_saveGalleryKey) ?? true;
      _notificationsEnabled = _prefs.getBool(_notificationsKey) ?? true;
    });
  }

  Future<void> _saveSettings() async {
    try {
      // Sauvegarder les paramètres Caméra
      await _prefs.setString(_resolutionKey, _selectedResolution);
      await _prefs.setString(_qualityKey, _selectedQuality);
      await _prefs.setString(_whiteBalanceKey, _whiteBalance);
      await _prefs.setDouble(_exposureKey, _exposureValue);
      await _prefs.setBool(_flashKey, _flashEnabled);
      await _prefs.setBool(_autoFocusKey, _autoFocus);
      await _prefs.setBool(_hdrKey, _hdrEnabled);
      await _prefs.setDouble(_zoomKey, _zoomLevel);
      await _prefs.setString(_videoFormatKey, _videoFormat);
      
      // Sauvegarder les paramètres Serveur
      await _prefs.setString(_serverIpKey, _serverIP);
      await _prefs.setInt(_serverPortKey, _serverPort);
      await _prefs.setBool(_autoStartKey, _autoStartServer);
      await _prefs.setBool(_broadcastKey, _enableBroadcast);
      await _prefs.setString(_streamQualityKey, _streamQuality);
      await _prefs.setInt(_maxConnectionsKey, _maxConnections);
      await _prefs.setBool(_authKey, _enableAuthentication);
      await _prefs.setString(_storagePathKey, _storagePath);
      
      // Sauvegarder les paramètres Client
      await _prefs.setString(_clientIpKey, _clientIP);
      await _prefs.setInt(_clientPortKey, _clientPort);
      await _prefs.setBool(_autoConnectKey, _autoConnect);
      await _prefs.setBool(_showPreviewKey, _showPreview);
      await _prefs.setString(_previewQualityKey, _previewQuality);
      await _prefs.setBool(_saveGalleryKey, _saveToGallery);
      await _prefs.setBool(_notificationsKey, _notificationsEnabled);
      
      // Forcer l'écriture sur le disque
      await _prefs.reload();
      
      _showSuccessMessage('Paramètres sauvegardés avec succès');
      Navigator.pop(context);
    } catch (e) {
      _showErrorMessage('Erreur lors de la sauvegarde: $e');
    }
  }

  Future<void> _resetToDefaults() async {
    try {
      // Réinitialiser les paramètres Caméra
      await _prefs.remove(_resolutionKey);
      await _prefs.remove(_qualityKey);
      await _prefs.remove(_whiteBalanceKey);
      await _prefs.remove(_exposureKey);
      await _prefs.remove(_flashKey);
      await _prefs.remove(_autoFocusKey);
      await _prefs.remove(_hdrKey);
      await _prefs.remove(_zoomKey);
      await _prefs.remove(_videoFormatKey);
      
      // Réinitialiser les paramètres Serveur
      await _prefs.remove(_serverIpKey);
      await _prefs.remove(_serverPortKey);
      await _prefs.remove(_autoStartKey);
      await _prefs.remove(_broadcastKey);
      await _prefs.remove(_streamQualityKey);
      await _prefs.remove(_maxConnectionsKey);
      await _prefs.remove(_authKey);
      await _prefs.remove(_storagePathKey);
      
      // Réinitialiser les paramètres Client
      await _prefs.remove(_clientIpKey);
      await _prefs.remove(_clientPortKey);
      await _prefs.remove(_autoConnectKey);
      await _prefs.remove(_showPreviewKey);
      await _prefs.remove(_previewQualityKey);
      await _prefs.remove(_saveGalleryKey);
      await _prefs.remove(_notificationsKey);
      
      // Recharger les préférences
      await _prefs.reload();
      
      setState(() {
        // Réinitialiser les paramètres caméra
        _selectedResolution = '1920x1080';
        _selectedQuality = 'Haute';
        _whiteBalance = 'Auto';
        _exposureValue = 0.0;
        _flashEnabled = false;
        _autoFocus = true;
        _hdrEnabled = false;
        _zoomLevel = 1.0;
        _videoFormat = 'MP4';
        
        // Réinitialiser les paramètres serveur
        _serverIP = '10.67.239.152';
        _serverPort = 8080;
        _autoStartServer = true;
        _enableBroadcast = true;
        _streamQuality = 'HD';
        _maxConnections = 5;
        _enableAuthentication = false;
        _storagePath = '/storage/emulated/0/CameraServer/';
        
        // Réinitialiser les paramètres client
        _clientIP = '10.67.239.152';
        _clientPort = 8080;
        _autoConnect = true;
        _showPreview = true;
        _previewQuality = 'Medium';
        _saveToGallery = true;
        _notificationsEnabled = true;
      });
      
      _showSuccessMessage('Paramètres réinitialisés aux valeurs par défaut');
    } catch (e) {
      _showErrorMessage('Erreur lors de la réinitialisation: $e');
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation'),
        content: const Text('Voulez-vous vraiment réinitialiser tous les paramètres ? Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToDefaults();
            },
            child: const Text('RÉINITIALISER', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.075,
        vertical: screenSize.height * 0.075,
      ),
      child: Container(
        width: screenSize.width * 0.85,
        height: screenSize.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // En-tête
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
                  const Icon(Icons.settings, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'PARAMÈTRES CAMÉRA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Onglets
            Container(
              color: Colors.blue[50],
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue[800],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.blue[800],
                tabs: const [
                  Tab(text: 'CAMÉRA'),
                  Tab(text: 'SERVEUR'),
                  Tab(text: 'CLIENT'),
                ],
              ),
            ),

            // Contenu des onglets
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Onglet Paramètres Caméra
                  _buildCameraSettingsTab(),
                  
                  // Onglet Paramètres Serveur
                  _buildServerSettingsTab(),
                  
                  // Onglet Paramètres Client
                  _buildClientSettingsTab(),
                ],
              ),
            ),

            // Boutons d'action
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showConfirmationDialog,
                      icon: const Icon(Icons.restore, size: 20),
                      label: const Text('RÉINITIALISER'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save, size: 20),
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

  Widget _buildCameraSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Paramètres Vidéo'),
          _buildDropdownSetting(
            'Résolution',
            _selectedResolution,
            _resolutions,
            (value) => setState(() => _selectedResolution = value!),
          ),
          _buildDropdownSetting(
            'Qualité Vidéo',
            _selectedQuality,
            _qualities,
            (value) => setState(() => _selectedQuality = value!),
          ),
          _buildDropdownSetting(
            'Format Vidéo',
            _videoFormat,
            _videoFormats,
            (value) => setState(() => _videoFormat = value!),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Paramètres Image'),
          _buildDropdownSetting(
            'Balance des Blancs',
            _whiteBalance,
            _whiteBalances,
            (value) => setState(() => _whiteBalance = value!),
          ),
          _buildSliderSetting(
            'Exposition',
            _exposureValue,
            -2.0,
            2.0,
            (value) => setState(() => _exposureValue = value),
          ),
          _buildSliderSetting(
            'Zoom',
            _zoomLevel,
            1.0,
            10.0,
            (value) => setState(() => _zoomLevel = value),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Fonctionnalités'),
          _buildToggleSetting(
            'Flash',
            _flashEnabled,
            (value) => setState(() => _flashEnabled = value),
          ),
          _buildToggleSetting(
            'Auto Focus',
            _autoFocus,
            (value) => setState(() => _autoFocus = value),
          ),
          _buildToggleSetting(
            'Mode HDR',
            _hdrEnabled,
            (value) => setState(() => _hdrEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildServerSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Configuration Réseau'),
          _buildTextInputSetting(
            'Adresse IP Serveur',
            _serverIP,
            (value) => setState(() => _serverIP = value),
            TextInputType.text,
          ),
          _buildNumberInputSetting(
            'Port Serveur',
            _serverPort.toString(),
            (value) => setState(() => _serverPort = int.tryParse(value) ?? 8080),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Paramètres Diffusion'),
          _buildDropdownSetting(
            'Qualité Stream',
            _streamQuality,
            _streamQualities,
            (value) => setState(() => _streamQuality = value!),
          ),
          _buildNumberInputSetting(
            'Connexions Max',
            _maxConnections.toString(),
            (value) => setState(() => _maxConnections = int.tryParse(value) ?? 5),
          ),
          _buildToggleSetting(
            'Diffusion Auto',
            _enableBroadcast,
            (value) => setState(() => _enableBroadcast = value),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Sécurité'),
          _buildToggleSetting(
            'Authentification',
            _enableAuthentication,
            (value) => setState(() => _enableAuthentication = value),
          ),
          _buildTextInputSetting(
            'Dossier Stockage',
            _storagePath,
            (value) => setState(() => _storagePath = value),
            TextInputType.text,
          ),
          _buildToggleSetting(
            'Démarrage Auto',
            _autoStartServer,
            (value) => setState(() => _autoStartServer = value),
          ),
        ],
      ),
    );
  }

  Widget _buildClientSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Configuration Connexion'),
          _buildTextInputSetting(
            'Adresse IP Client',
            _clientIP,
            (value) => setState(() => _clientIP = value),
            TextInputType.text,
          ),
          _buildNumberInputSetting(
            'Port Client',
            _clientPort.toString(),
            (value) => setState(() => _clientPort = int.tryParse(value) ?? 8080),
          ),
          _buildToggleSetting(
            'Connexion Auto',
            _autoConnect,
            (value) => setState(() => _autoConnect = value),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Paramètres Affichage'),
          _buildDropdownSetting(
            'Qualité Aperçu',
            _previewQuality,
            _previewQualities,
            (value) => setState(() => _previewQuality = value!),
          ),
          _buildToggleSetting(
            'Afficher Aperçu',
            _showPreview,
            (value) => setState(() => _showPreview = value),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Paramètres Stockage'),
          _buildToggleSetting(
            'Sauvegarde Galerie',
            _saveToGallery,
            (value) => setState(() => _saveToGallery = value),
          ),

          const SizedBox(height: 16),
          _buildSectionTitle('Notifications'),
          _buildToggleSetting(
            'Activer Notifications',
            _notificationsEnabled,
            (value) => setState(() => _notificationsEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue[800],
        ),
      ),
    );
  }

  Widget _buildDropdownSetting(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          DropdownButton<String>(
            value: value,
            onChanged: onChanged,
            items: options.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              );
            }).toList(),
            underline: const SizedBox(),
            isDense: true,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSetting(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue[800],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: Colors.blue[800],
            inactiveColor: Colors.grey[300],
          ),
        ],
      ),
    );
  }

  Widget _buildTextInputSetting(String label, String value, ValueChanged<String> onChanged, TextInputType keyboardType) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: TextEditingController(text: value),
            onChanged: onChanged,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInputSetting(String label, String value, ValueChanged<String> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: TextEditingController(text: value),
            onChanged: onChanged,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// Classe utilitaire pour accéder aux paramètres depuis d'autres parties de l'application
class CameraSettingsManager {
  static SharedPreferences? _prefs;

  static Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Getters pour les paramètres Caméra
  static Future<String> getResolution() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._resolutionKey) ?? '1920x1080';
  }

  static Future<String> getQuality() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._qualityKey) ?? 'Haute';
  }

  static Future<String> getWhiteBalance() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._whiteBalanceKey) ?? 'Auto';
  }

  

  static Future<double> getExposure() async {
    await _ensurePrefs();
    return _prefs!.getDouble(_CameraSettingsState._exposureKey) ?? 0.0;
  }

  static Future<bool> getFlashEnabled() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._flashKey) ?? false;
  }

  static Future<bool> getAutoFocus() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._autoFocusKey) ?? true;
  }

  static Future<bool> getHDREnabled() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._hdrKey) ?? false;
  }

  static Future<double> getZoomLevel() async {
    await _ensurePrefs();
    return _prefs!.getDouble(_CameraSettingsState._zoomKey) ?? 1.0;
  }

  static Future<String> getVideoFormat() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._videoFormatKey) ?? 'MP4';
  }

  // Getters pour les paramètres Serveur
 
  static Future<String> getServerIP() async {
    final prefs = await SharedPreferences.getInstance();
    // Retourne la valeur sauvegardée, ou la valeur par défaut '10.67.239.152' si rien n'est trouvé.
    return prefs.getString('server_ip') ?? '10.67.239.152'; 
  }

  static Future<int> getServerPort() async {
    final prefs = await SharedPreferences.getInstance();
    // Retourne la valeur sauvegardée, ou la valeur par défaut 8080 si rien n'est trouvé.
    return prefs.getInt('server_port') ?? 8080;
  }

  static Future<bool> getAutoStartServer() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._autoStartKey) ?? true;
  }

  static Future<bool> getEnableBroadcast() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._broadcastKey) ?? true;
  }

  static Future<String> getStreamQuality() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._streamQualityKey) ?? 'HD';
  }

  static Future<int> getMaxConnections() async {
    await _ensurePrefs();
    return _prefs!.getInt(_CameraSettingsState._maxConnectionsKey) ?? 5;
  }

  static Future<bool> getEnableAuthentication() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._authKey) ?? false;
  }

  static Future<String> getStoragePath() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._storagePathKey) ?? '/storage/emulated/0/CameraServer/';
  }

  // Getters pour les paramètres Client
  static Future<String> getClientIP() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._clientIpKey) ?? '10.67.239.152';
  }

  static Future<int> getClientPort() async {
    await _ensurePrefs();
    return _prefs!.getInt(_CameraSettingsState._clientPortKey) ?? 8080;
  }

  static Future<bool> getAutoConnect() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._autoConnectKey) ?? true;
  }

  static Future<bool> getShowPreview() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._showPreviewKey) ?? true;
  }

  static Future<String> getPreviewQuality() async {
    await _ensurePrefs();
    return _prefs!.getString(_CameraSettingsState._previewQualityKey) ?? 'Medium';
  }

  static Future<bool> getSaveToGallery() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._saveGalleryKey) ?? true;
  }

  static Future<bool> getNotificationsEnabled() async {
    await _ensurePrefs();
    return _prefs!.getBool(_CameraSettingsState._notificationsKey) ?? true;
  }
  // Ajoutez ces méthodes dans la classe CameraSettingsManager

 static Future<OperationMode> getOperationMode() async {
  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('operation_mode') ?? 'client';
  return mode == 'client' ? OperationMode.client : OperationMode.server;
}

 static Future<void> setServerIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
  }

  static Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('server_port', port);
  }

  static Future<void> setOperationMode(OperationMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('operation_mode', mode == OperationMode.client ? 'client' : 'server');
}

  static Future<void> setAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_connect', value);
  }
}




