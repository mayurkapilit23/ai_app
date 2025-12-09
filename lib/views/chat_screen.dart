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

// CHANGE: Use TickerProviderStateMixin instead of SingleTickerProviderStateMixin
class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
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
  late AnimationController
  _holdAnimationController; // <-- SECOND ANIMATION CONTROLLER

  // Timer for simulated amplitude (fallback)
  Timer? _simulationTimer;
  final Random _random = Random();

  // Hold & Speak variables
  bool _isButtonPressed = false;
  Timer? _holdTimer;
  final Duration _holdThreshold = const Duration(milliseconds: 300);
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // Drag/cancel tracking
  double _dragOffsetY = 0.0; // cumulative drag in vertical direction
  final double _cancelThreshold = 80.0; // pixels upward to cancel

  @override
  void initState() {
    super.initState();

    // Initialize pulse animation for recording state
    _pulseAnimationController = AnimationController(
      vsync: this, // <-- Now works with TickerProviderStateMixin
      duration: const Duration(milliseconds: 800),
    );

    // Initialize hold animation for button press feedback
    _holdAnimationController = AnimationController(
      vsync: this, // <-- Now works with TickerProviderStateMixin
      duration: const Duration(milliseconds: 300),
    );

    // Initialize text controller listener
    _textController.addListener(() {
      setState(() {});
    });

    // Initialize speech recognition
    _initSpeech();
  }

  Future<void> _restartListening() async {
    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            _textController.text = _lastWords;
            _textController.selection = TextSelection.collapsed(
              offset: _textController.text.length,
            );
          });
        },
        partialResults: true,
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(minutes: 5),
        onSoundLevelChange: _handleSoundLevelChange,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      print("Restart listen failed: $e");
    }
  }

  Future<void> _initSpeech() async {
    try {
      // Check and request microphone permission
      final status = await Permission.microphone.request();

      if (status.isGranted) {
        _speechAvailable = await _speech.initialize(
          onStatus: (status) async {
            _lastStatus = status;

            if (_isRecording) {
              if (status == "done" || status == "notListening") {
                // Speech engine auto-stopped → restart listen
                await Future.delayed(const Duration(milliseconds: 50));
                if (_isRecording) _restartListening();
              }
            }
            setState(() {
              // if (status == 'done' && _isRecording) {
              //   _stopRecording();
              // }
            });
          },

          onError: (error) {
            setState(() {
              _lastError = error.errorMsg;
              _isRecording = false;
              _isButtonPressed = false;
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
            // move caret to end
            _textController.selection = TextSelection.collapsed(
              offset: _textController.text.length,
            );
          });
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(minutes: 5),
        onSoundLevelChange: _handleSoundLevelChange,
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      );

      setState(() {
        _isRecording = true;
        _isListening = true;
        _lastWords = '';
        _lastError = '';
        _dragOffsetY = 0.0;
      });

      // Start pulse animation
      _pulseAnimationController.repeat(reverse: true);

      // Start wave animation
      _startWaveAnimation();

      // Start recording duration timer
      _startRecordingTimer();

      print("Started recording...");
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isButtonPressed = false;
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

  void _startRecordingTimer() {
    _recordingDuration = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRecording && mounted) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      } else {
        timer.cancel();
      }
    });
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
        _isButtonPressed = false;
        _currentAmplitude = 0.0;
      });

      // Reset wave heights
      _waveHeights = List.generate(7, (_) => 0.0);

      // Stop animations
      _stopWaveAnimation();
      _pulseAnimationController.stop();
      _pulseAnimationController.reset();
      _holdAnimationController.reverse();

      // Stop recording timer
      _recordingTimer?.cancel();
      _recordingTimer = null;

      print("Stopped recording after ${_recordingDuration.inSeconds} seconds");
    } catch (e) {
      print("Error stopping recording: $e");
    }
  }

  // Cancel recording (user slid up)
  void _cancelRecording() {
    _holdTimer?.cancel();
    _stopWaveAnimation();
    try {
      _speech.cancel();
    } catch (_) {}

    _pulseAnimationController.stop();
    _pulseAnimationController.reset();

    _recordingTimer?.cancel();
    _recordingTimer = null;

    setState(() {
      _isRecording = false;
      _isButtonPressed = false;
      _isListening = false;
      _currentAmplitude = 0.0;
      _lastWords = '';
      _textController.clear();
      _waveHeights = List.generate(7, (_) => 0.0);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Recording cancelled"),
          duration: Duration(seconds: 1),
        ),
      );
    }

    print("Recording cancelled by slide-up.");
  }

  // Handle button press (start holding)
  void _onButtonPressed() {
    setState(() {
      _isButtonPressed = true;
    });

    // Reset drag tracking
    _dragOffsetY = 0.0;

    // Start hold animation
    _holdAnimationController.forward();

    // Start hold timer
    _holdTimer = Timer(_holdThreshold, () {
      if (_isButtonPressed && !_isRecording) {
        _startRecording();
      }
    });
  }

  // Handle button release (stop holding)
  void _onButtonReleased() {
    // Cancel hold timer if it's still running
    _holdTimer?.cancel();

    // Reverse hold animation
    _holdAnimationController.reverse();

    // Reset drag tracking
    _dragOffsetY = 0.0;

    setState(() {
      _isButtonPressed = false;
    });

    // If recording is active, stop it
    if (_isRecording) {
      _stopRecording();
    }
  }

  // Handle button cancel (when finger leaves button area)
  void _onButtonCancel() {
    _onButtonReleased();
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

  @override
  void dispose() {
    _textController.dispose();
    _pulseAnimationController.dispose();
    _holdAnimationController.dispose();
    _stopWaveAnimation();
    _holdTimer?.cancel();
    _recordingTimer?.cancel();
    try {
      _speech.cancel();
    } catch (_) {}
    super.dispose();
  }

  List<ChatMessage> messages = [];

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
                  // List<ChatMessage> messages = [];

                  if (state is ChatLoaded) messages = state.messages;
                  if (state is ChatLoading) messages = state.messages;
                  if (state is ChatError) messages = state.messages;

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
          Expanded(flex: 2, child: Center(child: _buildVisualizer())),

          // Recording timer and stop button
          Column(
            // mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // // Recording timer
              // Container(
              //   padding: const EdgeInsets.all(8),
              //   decoration: BoxDecoration(
              //     color: Colors.red.withOpacity(0.1),
              //     borderRadius: BorderRadius.circular(20),
              //   ),
              //   child: Column(
              //     children: [
              //       // Slide to cancel hint
              //       Text(
              //         "Slide up to cancel",
              //         style: TextStyle(
              //           color: Colors.grey[700],
              //           fontSize: 10,
              //           fontWeight: FontWeight.w500,
              //         ),
              //       ),
              //       const SizedBox(height: 6),
              //
              //       Text(
              //         _formatDuration(_recordingDuration),
              //         style: TextStyle(
              //           color: Colors.red[700],
              //           fontSize: 14,
              //           fontWeight: FontWeight.bold,
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
              // const SizedBox(height: 8),

              // Stop button
              IconButton(
                onPressed: _stopRecording,
                icon: const Icon(Icons.stop, color: Colors.red),
                tooltip: 'Stop Recording',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Widget _buildVisualizer() {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording status
          Text(
            _isRecording ? "Recording... Speak now" : "Hold to speak",
            style: TextStyle(
              color: Colors.red[700],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

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
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.red.withOpacity(0.9),
                    Colors.orange.withOpacity(0.7),
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

          // Send/Hold & Speak Button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: _textController.text.trim().isEmpty || _isRecording
                ? _buildHoldToSpeakButton()
                : _buildSendButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldToSpeakButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _holdAnimationController,
        _pulseAnimationController,
      ]),
      builder: (context, child) {
        // Calculate scale based on hold animation
        double scale = 1.0;
        if (_isButtonPressed) {
          scale = 1.0 + _holdAnimationController.value * 0.3;
        } else if (_isRecording) {
          scale = 1.0 + _pulseAnimationController.value * 0.2;
        }

        // Calculate color based on state
        Color backgroundColor;
        if (_isRecording) {
          backgroundColor = Colors.red;
        } else if (_isButtonPressed) {
          // Gradient from blue to red while holding
          backgroundColor = Color.lerp(
            Colors.blue[500],
            Colors.red[500],
            _holdAnimationController.value,
          )!;
        } else {
          backgroundColor = Colors.blue[500]!;
        }

        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            // Core press/release behaviors
            onTapDown: (_) => _onButtonPressed(),
            onTapUp: (_) => _onButtonReleased(),
            onTapCancel: _onButtonCancel,
            // Also support pan gestures to detect upward slide (cancel)
            onPanStart: (_) {
              // reset cumulative drag
              _dragOffsetY = 0.0;
            },
            onPanUpdate: (details) {
              if (_isRecording || _isButtonPressed) {
                // accumulate vertical drag (positive is down, negative is up)
                _dragOffsetY += details.delta.dy;
                // If cumulative upward drag beyond threshold, cancel
                if (_dragOffsetY <= -_cancelThreshold) {
                  _cancelRecording();
                }
              }
            },
            onPanEnd: (_) {
              // If user pans but didn't cross threshold, do nothing special;
              // releasing the finger will trigger onTapUp -> _onButtonReleased which will stop recording if active.
            },
            // onLongPress: _isRecording ? null : _startRecording,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: backgroundColor.withOpacity(0.4),
                    blurRadius: _isRecording ? 15 : 8,
                    spreadRadius: _isRecording ? 2 : 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Hold progress indicator (only when holding, not recording)
                  if (_isButtonPressed && !_isRecording)
                    CircularProgressIndicator(
                      value: _holdAnimationController.value,
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      backgroundColor: Colors.white.withOpacity(0.3),
                    ),

                  // Pulsing effect when recording
                  if (_isRecording)
                    AnimatedBuilder(
                      animation: _pulseAnimationController,
                      builder: (context, child) {
                        return Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),

                  // Icon
                  Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
