import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_helper.dart';
import 'models/message.dart';
import 'services/device_identity.dart';
import 'services/bluetooth_service.dart';

import 'dart:convert';

part 'screens/home_screen.dart';
part 'widgets/devices_tab.dart';
part 'widgets/chats_tab.dart';
part 'widgets/conversation_tab.dart';
part 'widgets/new_chat_dialog.dart';

void main() {
  runApp(const MultiHopApp());
}

class MultiHopApp extends StatelessWidget {
  const MultiHopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MultiHop Messenger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
