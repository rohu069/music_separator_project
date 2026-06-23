import 'package:flutter/material.dart';

class MusicSeparatorScreen extends StatelessWidget {
  final bool isDarkMode;
  
  const MusicSeparatorScreen({super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Music Separator',
        style: TextStyle(
          color: isDarkMode ? Colors.white70 : Colors.black87,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          fontFamily: 'Helvetica',
        ),
      ),
    );
  }
}
