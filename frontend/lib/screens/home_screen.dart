import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/websocket_provider.dart';
import 'debate_screen.dart';
import '../widgets/sidebar_widget.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLastDebate();
    });
  }

    Future<void> _checkLastDebate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? lastDebateId = prefs.getString("last_debate_id");
    if (lastDebateId != null) {
      // ignore: use_build_context_synchronously
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DebateScreen(debateId: int.parse(lastDebateId)),
        ),
      );
    }
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('AI Brainstorming'),
    ),
    drawer: const SidebarWidget(),
    body: Container(
      color: Colors.white, // Set the background color to white
      child: Padding(
        padding: const EdgeInsets.all(50.0), // Add padding around the Column
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // const Text(
            //   "Sélectionnez un débat à gauche ou créez-en un nouveau",
            //   style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            //   textAlign: TextAlign.center,
            // ),
            const SizedBox(height: 20),
            const Icon(Icons.chat, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            FutureBuilder<List<dynamic>>(
              future: Provider.of<WebSocketProvider>(context, listen: false).getDebates(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else if (snapshot.hasData) {
                  final debates = snapshot.data!.reversed.take(5).toList();
                  return Column(
                    children: [
                      const Text(
                        'Derniers débats',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // Increased font size
                      ),
                      const SizedBox(height: 20),
                      ListView.builder(
                        shrinkWrap: true,
                        itemCount: debates.length,
                        itemBuilder: (context, index) {
                          final debate = debates[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DebateScreen(debateId: debate['id']),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [ // Added box shadow
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.5),
                                    spreadRadius: 2,
                                    blurRadius: 5,
                                    offset: const Offset(0, 3), // changes position of shadow
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: GptMarkdown(
                                  debate['topic'] ?? 'Untitled Debate',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                } else {
                return const Text('No debates found');
              }
            },
          ),
        ],
      ),
      ),
    ),
  );
}
}
