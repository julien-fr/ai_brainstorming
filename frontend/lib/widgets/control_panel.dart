import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import '../screens/debate_screen.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({Key? key}) : super(key: key);

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketProvider>(
      builder: (context, websocketProvider, child) {
        final bool isEnabled = !websocketProvider.isTimeout && !websocketProvider.isPaused && websocketProvider.isActive;

        return Column(
          children: [
            // Status and Control Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: websocketProvider.isTimeout
                                ? Colors.red[700]
                                : websocketProvider.isPaused
                                    ? Colors.orange[700]
                                    : websocketProvider.isActive
                                        ? Colors.green[700]
                                        : Colors.grey[600],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            websocketProvider.isTimeout
                                ? 'Timeout'
                                : websocketProvider.isPaused
                                    ? 'En pause'
                                    : websocketProvider.isActive
                                        ? 'Actif'
                                        : 'Inactif',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Control Buttons
                        Builder(
                          builder: (BuildContext context) {
                            final screen = context.findAncestorWidgetOfExactType<DebateScreen>();
                            final debateId = screen?.debateId;
                            if (debateId == null) return const SizedBox.shrink();

                            print(
                                "🔄 Building control buttons - Active: ${websocketProvider.isActive}, Paused: ${websocketProvider.isPaused}, Timeout: ${websocketProvider.isTimeout}");

                            // First check if we're in an active state
                            if (websocketProvider.isActive && !websocketProvider.isPaused && !websocketProvider.isTimeout) {
                              print("🎮 Showing active state controls");
                              // Both Pause and Stop buttons for active state
                              return Flexible(
                                child: Wrap(
                                  spacing: 8, // Horizontal spacing
                                  runSpacing: 8, // Vertical spacing
                                  children: [
                                    // ElevatedButton.icon(
                                    //   onPressed: () {
                                    //     final screen = context.findAncestorWidgetOfExactType<DebateScreen>();
                                    //     final debateId = screen?.debateId;
                                    //     if (debateId != null) {
                                    //       Provider.of<WebSocketProvider>(context, listen: false).pauseDebate(debateId);
                                    //     }
                                    //   },
                                    //   icon: const Icon(Icons.pause, color: Colors.white),
                                    //   label: const Text('Pause', style: TextStyle(color: Colors.white)),
                                    //   style: ElevatedButton.styleFrom(
                                    //     backgroundColor: Colors.orange[600],
                                    //     shape: RoundedRectangleBorder(
                                    //       borderRadius: BorderRadius.circular(20),
                                    //     ),
                                    //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    //   ),
                                    // ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        final screen = context
                                            .findAncestorWidgetOfExactType<
                                                DebateScreen>();
                                        final debateId = screen?.debateId;
                                        if (debateId != null) {
                                          Provider.of<WebSocketProvider>(
                                                  context,
                                                  listen: false)
                                              .stopDebate(debateId);
                                        }
                                      },
                                      icon: const Icon(Icons.stop,
                                          color: Colors.white),
                                      label: const Text('Stop',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            }
                            // Then check for paused or timeout states
                            else if (websocketProvider.isTimeout ||
                                websocketProvider.isPaused) {
                              print(
                                  "🎮 Showing restart controls for ${websocketProvider.isTimeout ? 'timeout' : 'paused'} state");
                              // Restart button for timeout/paused state
                              return ElevatedButton.icon(
                                onPressed: () =>
                                    Provider.of<WebSocketProvider>(context,
                                            listen: false)
                                        .restartDebate(),
                                icon: Icon(
                                  websocketProvider.isTimeout
                                      ? Icons.refresh
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  websocketProvider.isTimeout
                                      ? 'Redémarrer'
                                      : 'Reprendre',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              );
                            } else {
                              // Start button for inactive state
                              return ElevatedButton.icon(
                                onPressed: () async {
                                  final provider =
                                      Provider.of<WebSocketProvider>(context,
                                          listen: false);
                                  final screen = context
                                      .findAncestorWidgetOfExactType<
                                          DebateScreen>();
                                  final debateId = screen?.debateId;
                                  if (debateId != null) {
                                    await provider.restartDebate(
                                        debateId: debateId);
                                  }
                                },
                                icon: const Icon(Icons.play_arrow,
                                    color: Colors.white),
                                label: const Text('Démarrer',
                                    style: TextStyle(color: Colors.white)),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Comment Input
            // Padding(
            //   padding: const EdgeInsets.all(8.0),
            //   child: TextField(
            //     controller: _commentController,
            //     decoration: InputDecoration(
            //       labelText: 'Add Comment',
            //       border: const OutlineInputBorder(),
            //       suffixIcon: IconButton(
            //         icon: const Icon(Icons.send),
            //         onPressed: isEnabled ? () => _addComment(websocketProvider) : null,
            //       ),
            //     ),
            //     enabled: isEnabled,
            //   ),
            // ),
          ],
        );
      },
    );
  }
}
