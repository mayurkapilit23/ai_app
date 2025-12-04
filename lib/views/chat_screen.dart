import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../model/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  // Text controller
  final TextEditingController _textController = TextEditingController();

  // Speech to Text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  // Recording state
  bool _isRecording = false;
  bool _isListening = false;
  String _lastWords = '';
  String _lastError = '';
  String _lastStatus = '';

  // Audio visualization
  double _currentAmplitude = 0.0;
  List<double> _waveHeights = List.generate(7, (_) => 0.0);
  late AnimationController _pulseAnimationController;

  // Lottie animations
  static const String _waveAnimationPath = 'assets/voice1.json';

  // Timer for simulated amplitude (fallback)
  Timer? _simulationTimer;
  final Random _random = Random();

  // Flag to track if we should auto-send after recording stops
  bool _shouldAutoSend = false;

  @override
  void initState() {
    super.initState();

    // Initialize pulse animation
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Initialize text controller listener
    _textController.addListener(() {
      setState(() {});
    });

    // Initialize speech recognition
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      // Check and request microphone permission
      final status = await Permission.microphone.request();

      if (status.isGranted) {
        _speechAvailable = await _speech.initialize(
          onStatus: (status) {
            setState(() {
              _lastStatus = status;
              if (status == 'done' && _isRecording) {
                // Recording finished, stop it
                _stopRecording();
              }
            });
          },
          onError: (error) {
            setState(() {
              _lastError = error.errorMsg;
              _isRecording = false;
            });
          },
        );

        if (_speechAvailable) {
          print("Speech recognition initialized successfully");
        } else {
          print("Speech recognition not available");
        }
      } else {
        print("Microphone permission denied");
        _showPermissionDeniedDialog();
      }
    } catch (e) {
      print("Error initializing speech: $e");
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microphone Permission Required'),
        content: const Text(
          'This app needs microphone permission to use voice features. '
          'Please enable it in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startRecording() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            // Update the recognized text in the text field
            _lastWords = result.recognizedWords;
            _textController.text = _lastWords;
          });
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 10),
        onSoundLevelChange: _handleSoundLevelChange,
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
      );

      setState(() {
        _isRecording = true;
        _isListening = true;
        _lastWords = '';
        _lastError = '';
        _shouldAutoSend = false; // Reset auto-send flag
      });

      // Start wave animation
      _startWaveAnimation();

      print("Started recording...");
    } catch (e) {
      setState(() {
        _isRecording = false;
        _lastError = e.toString();
      });
      print("Error starting recording: $e");
    }
  }

  void _handleSoundLevelChange(double level) {
    if (!mounted) return;

    // Convert dB level to normalized amplitude (0-1)
    double normalizedLevel;

    if (_speechAvailable) {
      // Real amplitude from speech_to_text
      // Level ranges from -160 (quiet) to 0 (loud)
      normalizedLevel = (level + 160) / 160; // Convert to 0-1 range
      normalizedLevel = normalizedLevel.clamp(0.1, 1.0);
    } else {
      // Fallback simulation
      normalizedLevel = 0.3 + _random.nextDouble() * 0.7;
    }

    setState(() {
      _currentAmplitude = normalizedLevel;
    });

    // Update wave heights based on amplitude
    _updateWaveHeights();
  }

  void _updateWaveHeights() {
    final baseHeight = _currentAmplitude * 50.0;
    final timeOffset = DateTime.now().millisecondsSinceEpoch / 200.0;

    for (int i = 0; i < _waveHeights.length; i++) {
      // Create wave pattern with offset for each bar
      final offset = timeOffset + (i * 0.5);
      final waveFactor = sin(offset);

      // Calculate height with wave pattern
      double height = baseHeight * (0.5 + 0.5 * waveFactor);

      // Add some randomness for natural look
      height += _random.nextDouble() * 10;

      // Ensure minimum height
      height = height.clamp(8.0, 60.0);

      _waveHeights[i] = height;
    }
  }

  void _startWaveAnimation() {
    // Cancel any existing timers
    _stopWaveAnimation();

    // Start simulation timer if speech isn't available
    if (!_speechAvailable || _lastError.isNotEmpty) {
      _simulationTimer = Timer.periodic(const Duration(milliseconds: 150), (
        timer,
      ) {
        if (_isRecording && mounted) {
          // Simulate amplitude changes
          _handleSoundLevelChange(-100 + _random.nextDouble() * 60);
        } else {
          timer.cancel();
        }
      });
    }
  }

  void _stopWaveAnimation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  void _stopRecording() async {
    try {
      await _speech.stop();
      setState(() {
        _isRecording = false;
        _isListening = false;
        _currentAmplitude = 0.0;
      });

      // Reset wave heights
      _waveHeights = List.generate(7, (_) => 0.0);

      // Stop animations
      _stopWaveAnimation();

      print("Stopped recording");

      // DO NOT auto-send here anymore
      // The text is already in the text field
      // User can manually send by pressing send button
    } catch (e) {
      print("Error stopping recording: $e");
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatBloc>().add(SendChatMessage(text));
      _textController.clear();
      setState(() {
        _lastWords = '';
      });
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseAnimationController.dispose();
    _stopWaveAnimation();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Voice Chat Assistant",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages Area
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  List<ChatMessage> messages = [];

                  if (state is ChatLoaded) messages = state.messages;
                  if (state is ChatLoading) messages = state.messages;
                  if (state is ChatError) messages = state.messages;
                  // ADD Empty state handling
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        "Start a conversation...",
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    reverse: false,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _buildMessageBubble(message);
                    },
                  );
                },
              ),
            ),

            // Recording Overlay
            if (_isRecording) _buildRecordingOverlay(),

            // Input Area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isUser ? Colors.blue[600] : Colors.grey[200],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                bottomRight: isUser ? Radius.zero : const Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          // Visualizer
          Expanded(child: Center(child: _buildVisualizer())),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _stopRecording,
                icon: Icon(Icons.close),
                tooltip: 'Stop Recording',
              ),
              if (_lastWords.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: Icon(Icons.send),
                  tooltip: 'Send Message',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizer() {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Custom Wave Animation
          _buildCustomWaveAnimation(),
        ],
      ),
    );
  }

  Widget _buildCustomWaveAnimation() {
    return SizedBox(
      height: 20,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _waveHeights.asMap().entries.map((entry) {
            final index = entry.key;
            final height = entry.value;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              width: 8,
              height: max(height, 8),
              margin: EdgeInsets.only(
                left: index == 0 ? 0 : 4,
                right: index == _waveHeights.length - 1 ? 0 : 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.6),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Text Field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: _isRecording
                        ? "Speak now..."
                        : "Type a message...",
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    suffixIcon: _textController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey[500]),
                            onPressed: () {
                              _textController.clear();
                              setState(() {
                                _lastWords = '';
                              });
                            },
                          )
                        : null,
                  ),
                  maxLines: null,
                  onSubmitted: (value) => _sendMessage(),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Send/Mic Button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: _textController.text.trim().isEmpty || _isRecording
                ? _buildVoiceButton()
                : _buildSendButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isRecording ? 52 : 50,
      height: _isRecording ? 52 : 50,
      decoration: BoxDecoration(
        gradient: _isRecording
            ? RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [Colors.red[500]!, Colors.red[700]!],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue[500]!, Colors.blue[700]!],
              ),
        shape: BoxShape.circle,
        boxShadow: [
          if (_isRecording)
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            )
          else
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: IconButton(
        icon: _isRecording
            ? Stack(
                alignment: Alignment.center,
                children: [
                  // Pulsing effect
                  AnimatedBuilder(
                    animation: _pulseAnimationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + _pulseAnimationController.value * 0.3,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  ),
                  const Icon(Icons.mic, color: Colors.white, size: 24),
                ],
              )
            : const Icon(Icons.mic, color: Colors.white, size: 24),
        onPressed: _toggleRecording,
      ),
    );
  }

  Widget _buildSendButton() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.green[500]!, Colors.green[700]!],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.send, color: Colors.white, size: 24),
        onPressed: _sendMessage,
      ),
    );
  }
}
