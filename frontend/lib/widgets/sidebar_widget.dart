import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import '../screens/create_debate_screen.dart';
import '../screens/debate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_scroll/text_scroll.dart';

class SidebarWidget extends StatefulWidget {
  const SidebarWidget({Key? key}) : super(key: key);

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text('AI Brainstorming'),
            automaticallyImplyLeading: false,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CreateDebateScreen()),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'New Debate',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Consumer<WebSocketProvider>(
              builder: (context, websocketProvider, child) {
                return FutureBuilder<List<dynamic>>(
                  future: websocketProvider.getDebates(),
                  builder: (context, snapshot) {
                    print(
                        "📢 FutureBuilder rebuild - snapshot has data: ${snapshot.hasData}");

                    if (snapshot.hasData) {
                      return ListView.builder(
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final debate = snapshot.data![index];
                          print(
                              "📢 Affichage du débat : ${debate['topic']} - ID: ${debate['id']}");

                          return ListTile(
                            title: Text(
                              debate['topic'] ?? 'Untitled Debate',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString(
                                  'last_debate_id', debate['id'].toString());
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      DebateScreen(debateId: debate['id']),
                                ),
                              );
                            },
                            tileColor: Colors
                                .transparent, // Ensure tileColor is initially transparent
                            hoverColor: Colors.grey
                                .shade200, // Add a subtle hover color
                          );
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      return const CircularProgressIndicator();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
