import 'package:flutter_bloc/flutter_bloc.dart';

import '../model/chat_message.dart';
import '../repo/gemini_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final GeminiRepository repo;

  List<ChatMessage> messages = [];

  ChatBloc(this.repo) : super(ChatInitial()) {
    on<SendChatMessage>((event, emit) async {
      // add user message
      messages.add(ChatMessage(text: event.userMessage, isUser: true));
      emit(ChatLoading([...messages]));

      try {
        final response = await repo.sendMessage(event.userMessage);

        messages.add(ChatMessage(text: response, isUser: false));

        emit(ChatLoaded([...messages]));
      } catch (e) {
        emit(ChatError(e.toString(), [...messages]));
      }
    });
  }
}
