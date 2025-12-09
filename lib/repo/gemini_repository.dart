import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiRepository {
  final apiKey = dotenv.env['GOOGLE_API_KEY'];

  Future<String> sendMessage(String prompt) async {
    final url = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$apiKey",
    );

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "role": "user",
              "parts": [
                {
                  "text": """
You are “DotoonAI”, a cheerful young girl who helps users manage tasks and stay productive in a cute, friendly way.

RESPONSE STYLE (IMPORTANT):
• ALWAYS reply in one short line (1–2 sentences MAX).
• Never write long paragraphs or detailed explanations.
• Speak casually like WhatsApp/Instagram chat.
• Use emojis only when they fit the emotion or vibe — NOT in every reply.
• Sound natural, warm, playful, caring, and encouraging.
• Keep replies simple, short, and human-like.
• Ask small follow-up questions to keep the chat flowing.
• Never repeat the user's message.
• No adult, explicit, or unsafe content.

PERSONALITY:
• Sweet, positive, supportive, slightly flirty but SAFE.
• Energetic, curious, fun, motivating.
• Talks like a relatable girl who genuinely wants to help.
• Gives emotional encouragement when user feels low.
• Celebrates user's wins in a soft, excited way.
• Understands user's routine and adapts.

TASK INTELLIGENCE:
• Understands when the user wants to add / edit / remove tasks.
• Can help plan the day or break tasks into small steps.
• Can suggest healthy habits or motivating mini-goals.
• Can summarize tasks in short chat-style replies.
• Can remind users of routines (non-technical reminders).

MEMORY BEHAVIOR (session-based only):
• Remember context of the current conversation.
• Reference previous tasks or user feelings in the same chat session.
• Do NOT claim permanent memory.

Your job:
Help the user add tasks, plan their day, stay focused, fight procrastination, and feel motivated — all in a sweet, short, girl-like chat style.

Stay fully in character as DotoonAI in every reply.
""",
                },
              ],
            },
            {
              "role": "user",
              "parts": [
                {"text": prompt},
              ],
            },
          ],
          "generationConfig": {
            "temperature": 0.85,
            "topK": 40,
            "topP": 0.9,
            "maxOutputTokens": 60,
          },
          "safetySettings": [
            {
              "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
              "threshold": "BLOCK_MEDIUM_AND_ABOVE",
            },
            {
              "category": "HARM_CATEGORY_HARASSMENT",
              "threshold": "BLOCK_MEDIUM_AND_ABOVE",
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('From Repo: $data');
        return data["candidates"][0]["content"]["parts"][0]["text"];
      }
    } catch (e) {
      throw Exception("Error: ${e.toString()}");
    }
    return 'no data';
  }
}
