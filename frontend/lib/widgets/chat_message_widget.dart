import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../providers/websocket_provider.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class ChatMessageWidget extends StatelessWidget {
  final AIMessage message;

  const ChatMessageWidget({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Définition des couleurs et icônes par type d'agent
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    Color chipColor;
    IconData icon;

    switch (message.agentName.toLowerCase()) {
      case "summarizer":
        backgroundColor = Colors.orange[100]!;
        borderColor = Colors.orange[300]!;
        textColor = Colors.orange[900]!;
        chipColor = Colors.orange[700]!;
        icon = Icons.summarize;
        break;

      case "modérateur ia":
        backgroundColor = Colors.blue[100]!;
        borderColor = Colors.blue[300]!;
        textColor = Colors.blue[900]!;
        chipColor = Colors.blue[700]!;
        icon = Icons.support_agent;
        break;

      case "synthèse finale":
        backgroundColor = Colors.green[100]!;
        borderColor = Colors.green[300]!;
        textColor = Colors.green[900]!;
        chipColor = Colors.green[700]!;
        icon = Icons.article;
        break;

      default:
        backgroundColor = Colors.grey[100]!;
        borderColor = Colors.grey[300]!;
        textColor = Colors.black87;
        chipColor = Colors.blue[700]!;
        icon = Icons.person;
        break;
    }

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: textColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  message.agentName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    message.modelUsed,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  avatar: const Icon(Icons.memory, color: Colors.white),
                  backgroundColor: chipColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                const Spacer(),
                InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content.replaceFirst('${message.agentName} : ', '')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copié dans le presse-papiers'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.copy, size: 18, color: Colors.grey),
                    )),
                Tooltip(
                  message: 'Modèle utilisé : ${message.modelUsed}',
                  child: Icon(
                    Icons.info_outline,
                    color: textColor,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Stack(
              children: [
                GptMarkdown(
                  message.content.replaceFirst('${message.agentName} : ', ''), // Nettoyage du message
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: message.agentName.toLowerCase() == "synthétiseur" ? FontWeight.w600 : FontWeight.normal,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(message.timestamp)),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
