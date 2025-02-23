import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/websocket_provider.dart';
import '../widgets/chat_message_widget.dart';
import '../widgets/control_panel.dart';
import '../config.dart';
import 'package:text_scroll/text_scroll.dart';


class DebateScreen extends StatefulWidget {
  final int? debateId;

  const DebateScreen({Key? key, this.debateId}) : super(key: key);

  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

class _DebateScreenState extends State<DebateScreen> {
  final ScrollController _scrollController = ScrollController();
  final _topicController = TextEditingController();
  final _messageController = TextEditingController();
  final _modelController = TextEditingController(); // Controller for model selection
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic> _debate = {};
  int _numberOfAgents = 0;
  List<TextEditingController> _agentNameControllers = [];
  List<TextEditingController> _agentModelControllers = [];
  List<TextEditingController> _agentTemperatureControllers = [];
  List<double> _agentTemperatureValues = [];
  late WebSocketChannel channel;
  List<dynamic> messages = [];
  String wsUrl = API_BASEURL.replaceFirst("http", "ws");

  @override
  void initState() {
    super.initState();
    if (widget.debateId != null) {
      print("🔄 Initializing debate ${widget.debateId}");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _restoreDebate();
        Provider.of<WebSocketProvider>(context, listen: false).connect(WS_BASEURL, widget.debateId!);
      });
    }
  }

  Future<void> _restoreDebate() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
      print("🔄 Restoring debate ${widget.debateId}");

      // 1. Get initial debate state
      final debate = await websocketProvider.getDebate(widget.debateId!);
      setState(() {
        _debate = debate;
        print("📥 Initial debate state: $_debate");
      });

      // 2. Update provider state
      //websocketProvider.updateDebateState(_debate);
      //print("🔄 Provider state updated - Active: ${websocketProvider.isActive}, Paused: ${websocketProvider.isPaused}");

      // 3. Load messages
      print("📥 Messages loaded");

      // 4. If debate is active or we need to restart it, use restartDebate
      //if (_debate['status'] == 'ACTIVE' || _debate['is_active'] == true) {
      //  print("✅ Debate is active, restarting WebSocket connection");
      //  await websocketProvider.restartDebate();
      //} else {
      //  print("i️ Debate is not active, current status: ${_debate['status']}");
      //}

    } catch (e) {
      print("❌ Error restoring debate: $e");
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(DebateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _agentNameControllers = List.generate(_numberOfAgents, (_) => TextEditingController());
    _agentModelControllers = List.generate(_numberOfAgents, (_) => TextEditingController());
    _agentTemperatureControllers = List.generate(_numberOfAgents, (_) => TextEditingController());
    _agentTemperatureValues = List.generate(_numberOfAgents, (_) => 1.0);
  }

  Future<void> _fetchDebate() async {
    print("🔍 _fetchDebate() appelé");
    if (_debate.isNotEmpty) return; // Évite les appels multiples

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
      final debate = await websocketProvider.getDebate(widget.debateId!);

      setState(() {
        _debate = debate;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    _messageController.dispose();
    _modelController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createDebate() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
      // Collect agent data
      List<Map<String, dynamic>> agentsData = [];
      for (int i = 0; i < _numberOfAgents; i++) {
        agentsData.add({
          "name": _agentNameControllers[i].text,
          "model_used": _agentModelControllers[i].text,
          "temperature": _agentTemperatureValues[i],
        });
      }
      // Create debate with agents data
      print("agentsData: $agentsData");
      await websocketProvider.createDebate(_topicController.text, agents: agentsData);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage(WebSocketProvider websocketProvider) async {
    if (_messageController.text.isEmpty) return;
    // Send message with model information
    final message = {
      "content": _messageController.text,
      "model_used": _modelController.text, // Include selected model
    };
    websocketProvider.addComment(jsonEncode(message)); // Send as JSON
    _messageController.clear();
  }

  Widget _buildAgentForm(int index) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Agent ${index + 1}'),
          TextFormField(
            controller: _agentNameControllers[index],
            decoration: const InputDecoration(labelText: 'Agent Name'),
          ),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Model Used'),
            value: _agentModelControllers[index].text.isNotEmpty ? _agentModelControllers[index].text : "google/gemini-2.0-flash-001",
            items: const [
              DropdownMenuItem(
                value: "google/gemini-2.0-pro-exp-02-05:free",
                child: Text("google/gemini-2.0-pro-exp-02-05:free"),
              ),
              DropdownMenuItem(
                value: "openai/gpt-4o-2024-11-20",
                child: Text("openai/gpt-4o-2024-11-20"),
              ),
              DropdownMenuItem(
                value: "deepseek/deepseek-r1:free",
                child: Text("deepseek/deepseek-r1:free"),
              ),
            ],
            onChanged: (value) {
              _agentModelControllers[index].text = value!;
            },
          ),
          Slider(
            value: _agentTemperatureValues[index],
            min: 0,
            max: 2,
            divisions: 20,
            label: _agentTemperatureValues[index].toStringAsFixed(1),
            onChanged: (double value) {
              setState(() {
                _agentTemperatureValues[index] = value;
                _agentTemperatureControllers[index].text = value.toString();
              });
            },
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextScroll(_debate['topic'] ?? 'AI Brainstorming'),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Conditionally render the form based on screen width
                if (widget.debateId == null)
                  Builder(
                    builder: (BuildContext context) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (screenWidth > 600) {
                        // Wide screen: Display form side-by-side with chat
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _topicController,
                                    decoration: const InputDecoration(
                                      labelText: 'Debate Topic',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    decoration: const InputDecoration(
                                        labelText: 'Number of Agents'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      setState(() {
                                        _numberOfAgents =
                                            int.tryParse(value) ?? 0;
                                        _agentNameControllers =
                                            List.generate(_numberOfAgents,
                                                (_) => TextEditingController());
                                        _agentModelControllers =
                                            List.generate(_numberOfAgents,
                                                (_) => TextEditingController());
                                        _agentTemperatureControllers =
                                            List.generate(_numberOfAgents,
                                                (_) => TextEditingController());
                                        _agentTemperatureValues =
                                            List.generate(_numberOfAgents,
                                                (_) => 1.0);
                                      });
                                    },
                                  ),
                                  ...List.generate(_numberOfAgents,
                                      (index) => _buildAgentForm(index)),
                                  SizedBox(
                                    width: 170,
                                    child: ElevatedButton(
                                      onPressed:
                                          _isLoading ? null : _createDebate,
                                      child: _isLoading
                                          ? const CircularProgressIndicator()
                                          : const Text('Create Debate'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16), // Add spacing
                            Expanded(
                              child: Column(
                                children: [
                                  if (_error != null)
                                    Text(
                                      _error!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  const ControlPanel(),
                                ],
                              )
                            ),
                          ],
                        );
                      } else {
                        // Narrow screen: Display form above chat
                        return Column(
                          children: [
                            TextField(
                              controller: _topicController,
                              decoration: const InputDecoration(
                                labelText: 'Debate Topic',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              decoration: const InputDecoration(
                                  labelText: 'Number of Agents'),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                setState(() {
                                  _numberOfAgents = int.tryParse(value) ?? 0;
                                  _agentNameControllers = List.generate(
                                      _numberOfAgents,
                                      (_) => TextEditingController());
                                  _agentModelControllers = List.generate(
                                      _numberOfAgents,
                                      (_) => TextEditingController());
                                  _agentTemperatureControllers = List.generate(
                                      _numberOfAgents,
                                      (_) => TextEditingController());
                                  _agentTemperatureValues = List.generate(
                                      _numberOfAgents, (_) => 1.0);
                                });
                              },
                            ),
                            ...List.generate(_numberOfAgents,
                                (index) => _buildAgentForm(index)),
                            SizedBox(
                              width: 170,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _createDebate,
                                child: _isLoading
                                    ? const CircularProgressIndicator()
                                    : const Text('Create Debate'),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                if (widget.debateId != null && _error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                if (widget.debateId != null)
                  Expanded(
                    child: Consumer<WebSocketProvider>(
                      builder: (context, websocketProvider, child) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _scrollToBottom());
                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: websocketProvider.messages.length,
                          itemBuilder: (context, index) {
                            final message = websocketProvider.messages[index];
                            return ChatMessageWidget(message: message);
                          },
                        );
                      },
                    ),
                  ),
                if (widget.debateId != null) const ControlPanel(),
                if (widget.debateId != null) const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}
