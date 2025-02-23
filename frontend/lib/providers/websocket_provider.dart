import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import '../config.dart' show WS_BASEURL, API_BASEURL;

enum DebateStatus { ACTIVE, PAUSED, TIMEOUT, STOPPED, UNKNOWN }

class AIMessage {
  final String agentName;
  final String modelUsed;
  final double temperature;
  final String content;
  final String timestamp;
  final int debateId;
  final bool isModerator;
  final bool isFinal;
  bool consensusReached = false;

  AIMessage({
    required this.agentName,
    required this.modelUsed,
    required this.temperature,
    required this.content,
    required this.timestamp,
    required this.debateId,
    required this.consensusReached,
    required this.isModerator,
    required this.isFinal,
  });

  AIMessage copyWith({
    String? agentName,
    String? modelUsed,
    double? temperature,
    String? content,
    String? timestamp,
    int? debateId,
    bool? consensusReached = false,
    bool? isModerator,
    bool? isFinal,
  }) {
    return AIMessage(
      agentName: agentName ?? this.agentName,
      modelUsed: modelUsed ?? this.modelUsed,
      temperature: temperature ?? this.temperature,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      debateId: debateId ?? this.debateId,
      consensusReached: consensusReached ?? this.consensusReached,
      isModerator: isModerator ?? this.isModerator,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      agentName: json['agent_name']?.toString() ?? "Unknown", // Suppression de utf8.decode
      modelUsed: json['model_used'] ?? "Unknown",
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      content: json['content']?.toString() ?? "Message vide.",
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      debateId: json['debate_id'] ?? 0,
      consensusReached: json['consensus_reached'] ?? false,
      isModerator: json['is_moderator'] ?? false,
      isFinal: json['is_final'] ?? false,
    );
  }
}

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isPaused = false;
  bool _isActive = false;
  bool _isTimeout = false;
  List<AIMessage> _messages = [];
  String? _url;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 10;
  int? _debateId;
  Map<String, AIMessage> _pendingMessages = {};

  bool get isConnected => _isConnected;
  List<AIMessage> get messages => _messages;
  bool get isPaused => _isPaused;
  bool get isActive => _isActive;
  bool get isTimeout => _isTimeout;
  int? get debateId => _debateId;

  Future<void> connect(String baseUrl, int debateId) async {
    _url = baseUrl;
    _debateId = debateId;
    try {
      // Récupération de l'historique des messages avant d'ouvrir le WebSocket
      final messagesHistory = await getDebateMessages(debateId);
      _messages = messagesHistory.map((json) => AIMessage.fromJson(json)).toList();
      notifyListeners(); // Met à jour l'affichage avant le WebSocket

      // Connexion WebSocket
      final wsUrl = '$_url/ws/debate/$debateId';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _channel!.stream.listen(_handleMessage, onError: _handleError, onDone: _onDone);

      // Envoie un message d'initialisation pour signaler la connexion
      _sendInitializationMessage(debateId);
    } catch (e) {
      _reconnect();
    }
  }

  Future<List<dynamic>> getDebateMessages(int debateId) async {
    final url = '$API_BASEURL/debates/$debateId/messages/';
    final headers = {'Content-Type': 'application/json'};

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  void _sendInitializationMessage(int debateId) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({"type": "initialize", "debate_id": debateId}));
      print("⬆️ Initialization message sent to WebSocket: { type: initialize, debate_id: $debateId }");
    } else {
      print("❌ WebSocket is not connected. Cannot send initialization message.");
    }
  }

  void _handleMessage(dynamic data) {
    print("📥 Message reçu via WebSocket : $data");

    try {
      final jsonData = jsonDecode(data);

      if (jsonData.containsKey("type")) {
        switch (jsonData["type"]) {
          case "debate_paused":
            _handleDebateStatus({'status': 'paused'});
            return;
          case "debate_timeout":
            _handleDebateStatus({'status': 'timeout'});
            return;
          case "debate_status":
            _handleDebateStatus(jsonData);
            return;
          case "debate_stopped":
            _handleDebateStatus({'status': 'stopped'});
            return;
        }
      }

      // If we receive a regular message (not a status update), ensure we're in the right state
      if (!jsonData.containsKey("type")) {
        if (!_isActive || _isPaused || _isTimeout) {
          print("📥 Received message while in incorrect state - Fixing state");
          _handleDebateStatus({'status': 'active'});
        }
      }

      // Parse and handle the message
      final message = AIMessage.fromJson(jsonData);
      print("📥 Parsing message from ${message.agentName}");

      try {
        if (!_pendingMessages.containsKey(message.agentName)) {
          print("✨ Creating new pending message for ${message.agentName}");
          _pendingMessages[message.agentName] = message.copyWith(content: "");
        }

        final newContent = message.content;
        final existingContent = _pendingMessages[message.agentName]!.content;

        // Replace the content if newContent contains existingContent, otherwise append
        if (newContent.contains(existingContent)) {
          print("📝 Replacing content from ${message.agentName}");
          _pendingMessages[message.agentName] = _pendingMessages[message.agentName]!.copyWith(
            content: newContent,
          );
        } else {
          print("📝 Appending new content from ${message.agentName}");
          _pendingMessages[message.agentName] = _pendingMessages[message.agentName]!.copyWith(
            content: existingContent + newContent,
          );
        }
        notifyListeners();

        if (message.isFinal) {
          // This check is now more effective because _pendingMessages will have correct content
          if (!_messages.any((m) => m.agentName == message.agentName && m.content == _pendingMessages[message.agentName]!.content)) {
            _messages.add(_pendingMessages[message.agentName]!);
          }
          _pendingMessages.remove(message.agentName);
          print("✅ Final message added from ${message.agentName}");
        }
      } catch (e) {
        print("❌ Error handling message: $e");
      }

      print("🔄 Mise à jour UI - Messages actuels : ${_messages.map((m) => m.content).toList()}");
    } catch (e) {
      print("❌ Erreur de décodage WebSocket: $e");
      print('❌ Raw WebSocket data: $data');
    }
  }

  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    notifyListeners();
    _reconnect();
  }

  void _onDone() {
    print('WebSocket connection closed.');
    _isConnected = false;
    notifyListeners();
    _reconnect();
  }

  void _reconnect() {
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(seconds: _reconnectAttempts * 2);
      print('Attempting to reconnect in ${delay.inSeconds} seconds (attempt $_reconnectAttempts/$_maxReconnectAttempts)');
      _reconnectTimer = Timer(delay, () {
        print('Reconnecting to WebSocket...');
        connect(_url!, _debateId ?? -1);
      });
    } else {
      print('Max reconnect attempts reached. Giving up.');
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  Future<void> addComment(String comment) async {
    if (_debateId == null) {
      print('Debate ID is not set.');
      return;
    }

    final url = '$API_BASEURL/debates/$_debateId';
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'agent_name': 'Moderator',
      'model_used': 'System',
      'temperature': 0.0,
      'content': comment,
      'is_moderator': true,
    });

    try {
      final response = await http.post(Uri.parse(url), headers: headers, body: body);
      if (response.statusCode != 200) {
        print('Failed to add comment: ${response.statusCode}');
      }
    } catch (e) {
      print('Error adding comment: $e');
    }
  }

  Future<void> pauseDebate(int debateId) async {
    print("🔄 Attempting to pause/unpause debate $debateId via WebSocket");
    if (_isConnected) {
      _channel!.sink.add(jsonEncode({"type": "pause", "debate_id": debateId}));
    } else {
      print("WebSocket is not connected. Please try again.");
    }
  }

  Future<void> restartDebate({int? debateId}) async {
    print("🔄 Attempting to restart debate $debateId via WebSocket");
    if (_isConnected && debateId != null) {
      _channel!.sink.add(jsonEncode({"type": "restart", "debate_id": debateId}));
    } else {
      print("WebSocket is not connected or debate ID is not set. Please try again.");
    }
  }

  Future<void> stopDebate(int debateId) async {
    print("🔄 Attempting to stop debate $debateId via WebSocket");
    if (_isConnected) {
      _channel!.sink.add(jsonEncode({"type": "stop", "debate_id": debateId}));
    } else {
      print("WebSocket is not connected. Please try again.");
    }
  }

  void _handleDebateStatus(Map<String, dynamic> statusData) {
    DebateStatus debateStatus = DebateStatus.UNKNOWN;
    final statusString = statusData['status']?.toString().toUpperCase();
    print("📥 Received debate status: $statusString");

    switch (statusString) {
      case 'ACTIVE':
        debateStatus = DebateStatus.ACTIVE;
        break;
      case 'PAUSED':
        debateStatus = DebateStatus.PAUSED;
        break;
      case 'TIMEOUT':
        debateStatus = DebateStatus.TIMEOUT;
        break;
      case 'STOPPED':
        debateStatus = DebateStatus.STOPPED;
        break;
      default:
        print("❌ Unknown debate status: $statusString");
        debateStatus = DebateStatus.UNKNOWN;
        break;
    }

    bool stateChanged = false;

    if (_isActive != (debateStatus == DebateStatus.ACTIVE) ||
        _isPaused != (debateStatus == DebateStatus.PAUSED) ||
        _isTimeout != (debateStatus == DebateStatus.TIMEOUT)) {
      _isActive = (debateStatus == DebateStatus.ACTIVE);
      _isPaused = (debateStatus == DebateStatus.PAUSED);
      _isTimeout = (debateStatus == DebateStatus.TIMEOUT);
      stateChanged = true;

      print("✅ Debate is now $debateStatus");
    }

    if (stateChanged) {
      print("🔄 State updated - Active: $_isActive, Paused: $_isPaused, Timeout: $_isTimeout");
      notifyListeners();
    }
  }

  void sendRestartMessage() {
    if (_channel == null || _debateId == null) {
      print("WebSocket is not connected or debate ID is not set.");
      return;
    }

    print("Sending restart message for debate ID: $_debateId");
    _channel!.sink.add(jsonEncode({"type": "restart", "debate_id": _debateId}));
  }

  void updateDebateState(Map<String, dynamic> debateData) {
    print("📥 Updating debate state with data: $debateData");

    if (debateData.containsKey('status')) {
      final status = debateData['status'];
      print("📥 Found status in data: $status");
      _handleDebateStatus({'status': status});
    } else {
      print("📥 No status found, using individual flags");
      _isPaused = debateData['is_paused'] ?? false;
      _isActive = debateData['is_active'] ?? false;
      _isTimeout = debateData['status']?.toString().toUpperCase() == 'TIMEOUT';
      notifyListeners();
    }

    print("🔄 State updated - Active: $_isActive, Paused: $_isPaused, Timeout: $_isTimeout");
  }

  void restoreMessages(List<dynamic> messageList) {
    _messages.clear();
    _messages = messageList.map((json) => AIMessage.fromJson(json)).toList();
    print("🔄 Messages restaurés dans WebSocketProvider : ${_messages.length}");
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  Future<int?> createDebate(String topic, {List<Map<String, dynamic>>? agents}) async {
    final url = '$API_BASEURL/debates/';
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'topic': topic, 'agents': agents});

    try {
      final response = await http.post(Uri.parse(url), headers: headers, body: body);
      if (response.statusCode == 200) {
        final debate = jsonDecode(response.body);
        _debateId = debate['id'];
        notifyListeners();
        return debate['id'];
      } else {
        print('Failed to create debate: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error creating debate: $e');
      return null;
    }
  }

  Future<List<dynamic>> getDebates() async {
    final url = '$API_BASEURL/debates/';
    final headers = {'Content-Type': 'application/json'};

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        print('Failed to get debates: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting debates: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getDebate(int debateId) async {
    final url = '$API_BASEURL/debates/$debateId';
    final headers = {'Content-Type': 'application/json'};

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        print('Failed to get debate: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('Error getting debate: $e');
      return {};
    }
  }
}
