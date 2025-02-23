import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/websocket_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    const MyApp(),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => WebSocketProvider(),
      child: MaterialApp(
        title: 'AI Brainstorming',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Consistent padding
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 3,
              textStyle: const TextStyle(fontSize: 16),
              backgroundColor: Colors.blue, // Default primary color
              foregroundColor: Colors.white,
            ).copyWith(
              overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
                if (states.contains(MaterialState.hovered)) {
                  return Colors.blue.shade300; // Slightly darker hover color
                }
                if (states.contains(MaterialState.pressed)) {
                  return Colors.blue.shade400; // Darker press color
                }
                return null;
              }),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: Colors.blue.shade700,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.blue.shade700,
            overlayColor: Colors.blue.shade100.withOpacity(0.3),
            valueIndicatorColor: Colors.blue.shade700,
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.white,
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
