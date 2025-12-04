abstract class ChatEvent {}

class SendChatMessage extends ChatEvent {
  final String userMessage;
  SendChatMessage(this.userMessage);
}
