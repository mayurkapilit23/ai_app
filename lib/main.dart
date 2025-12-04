import 'package:ai_app/repo/gemini_repository.dart';
import 'package:ai_app/views/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'bloc/chat_bloc.dart';

void main() async {
  await dotenv.load();
  runApp(
    MultiBlocProvider(
      providers: [BlocProvider(create: (_) => ChatBloc(GeminiRepository()))],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: ChatScreen());
  }
}
