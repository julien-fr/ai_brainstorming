import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import 'debate_screen.dart';
import 'dart:convert';

class CreateDebateScreen extends StatefulWidget {
  const CreateDebateScreen({Key? key}) : super(key: key);

  @override
  State<CreateDebateScreen> createState() => _CreateDebateScreenState();
}

class _CreateDebateScreenState extends State<CreateDebateScreen> {
  final _topicController = TextEditingController();
  int _numberOfAgents = 0;
  List<TextEditingController> _agentNameControllers = [];
  List<TextEditingController> _agentModelControllers = [];
  List<TextEditingController> _agentContextControllers = [];
  List<double> _agentTemperatureValues = [];

  @override
  void initState() {
    super.initState();
    _agentNameControllers = List.generate(1, (_) => TextEditingController());
    _agentModelControllers = List.generate(1, (_) => TextEditingController());
    _agentContextControllers = List.generate(1, (_) => TextEditingController());
    _agentTemperatureValues = List.generate(1, (_) => 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Debate'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _topicController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Debate Topic',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _numberOfAgents++;
                  _agentNameControllers.add(TextEditingController());
                  _agentModelControllers.add(TextEditingController());
                  _agentContextControllers.add(TextEditingController());
                  _agentTemperatureValues.add(1.0);
                });
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)
                ),
              ),
              child: const Text('Add Agent'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _numberOfAgents,
                itemBuilder: (context, index) {
                  return Column(
                    children: [
                      _buildAgentForm(index),
                      if (index < _numberOfAgents - 1) SizedBox(height:10), // Add separator
                      if (index == _numberOfAgents - 1) ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _numberOfAgents++;
                              _agentNameControllers.add(TextEditingController());
                              _agentModelControllers.add(TextEditingController());
                              _agentContextControllers.add(TextEditingController());
                              _agentTemperatureValues.add(1.0);
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)
                            ),
                          ),
                          child: const Text('Add Agent'),
                        ),
                      ]
                    ],
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Collect agent data
                List<Map<String, dynamic>> agentsData = [];
                for (int i = 0; i < _numberOfAgents; i++) {
                  final agentData = {
                    "name": _agentNameControllers[i].text,
                    "model_used": _agentModelControllers[i].text,
                    "temperature": _agentTemperatureValues[i],
                    "context": _agentContextControllers[i].text,
                  };
                  print("agentData: $agentData");
                  agentsData.add(agentData);
                }

                print('Sending data: ${jsonEncode({'topic': _topicController.text, 'agents': agentsData})}');

                // Create debate
                final websocketProvider =
                    Provider.of<WebSocketProvider>(context, listen: false);
                final debateId = await websocketProvider.createDebate(
                  _topicController.text,
                  agents: agentsData,
                );

                // Navigate to the DebateScreen
                if (debateId != null) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DebateScreen(debateId: debateId),
                    ),
                  );
                } else {
                  // Handle the error case where debate creation failed
                  print('Failed to create debate');
                  // You might want to show an error message to the user
                }
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)
                )
              ),
              child: const Text('Create Debate'),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildAgentForm(int index) {
      return Card(
        margin: const EdgeInsets.all(8.0),
        elevation: 5.0, // Increased elevation for a more prominent shadow
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
                child: Text('Agent ${index + 1}'),
              ),
              SizedBox(height:10),
              TextFormField(
                controller: _agentNameControllers[index],
                decoration: const InputDecoration(labelText: 'Agent Name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Model Used'),
                items: const [
                  DropdownMenuItem(
                    value: "google/gemini-2.0-flash-001",
                    child: Text("google/gemini-2.0-flash-001"),
                  ),
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
                  DropdownMenuItem(
                    value: "openai/gpt-4o-2024-11-20",
                    child: Text("openai/gpt-4o-2024-11-20"),
                  ),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _agentModelControllers[index].text = value!;
                  });
                },
              ),
              const SizedBox(height: 8),
              DefaultTextStyle(
                style: const TextStyle(fontSize: 16, color: Colors.black),
                child: Text("Temperature:"),
              ),
              Slider(
                value: _agentTemperatureValues[index],
                min: 0,
                max: 2,
                divisions: 20,
                label: _agentTemperatureValues[index].toStringAsFixed(1),
                onChanged: (double value) =>
                    setState(() => _agentTemperatureValues[index] = value),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _agentContextControllers[index],
                decoration: const InputDecoration(labelText: 'Rôle de l\'agent'),
              ),
            ],
          ),
        ),
      );
    }
  }
