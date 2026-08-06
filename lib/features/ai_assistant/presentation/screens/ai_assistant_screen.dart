import 'package:flutter/material.dart';

import 'ai_chat_screen.dart';
import 'ai_insights_screen.dart';
import 'ai_settings_screen.dart';

final class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('i Book AI Assistant'),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat), text: 'AI Chat'),
              Tab(icon: Icon(Icons.insights), text: 'Insights Inbox'),
              Tab(icon: Icon(Icons.settings), text: 'AI Settings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AiChatScreen(),
            AiInsightsScreen(),
            AiSettingsScreen(),
          ],
        ),
      ),
    );
  }
}
