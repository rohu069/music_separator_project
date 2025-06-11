import 'dart:html' as html;
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MusicSeparatorApp());
}

class MusicSeparatorApp extends StatefulWidget {
  const MusicSeparatorApp({super.key});

  @override
  State<MusicSeparatorApp> createState() => _MusicSeparatorAppState();
}

class _MusicSeparatorAppState extends State<MusicSeparatorApp> {
  bool isDarkMode = false;

  void toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Separator',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.light,
        cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.dark,
        cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: UploadPage(onToggleTheme: toggleTheme, isDarkMode: isDarkMode),
    );
  }
}

class UploadPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const UploadPage({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class SeparatedFile {
  final String originalFileName;
  final Map<String, String> stemsUrls;

  SeparatedFile({required this.originalFileName, required this.stemsUrls});

  Map<String, dynamic> toJson() => {
    'originalFileName': originalFileName,
    'stemsUrls': stemsUrls,
  };

  factory SeparatedFile.fromJson(Map<String, dynamic> json) => SeparatedFile(
    originalFileName: json['originalFileName'],
    stemsUrls: Map<String, String>.from(json['stemsUrls']),
  );
}

class WaveformPainter extends CustomPainter {
  final Animation<double> animation;
  final bool isDarkMode;

  WaveformPainter({required this.animation, required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color =
              isDarkMode
                  ? Colors.purpleAccent.withOpacity(0.3)
                  : Colors.deepPurple.withOpacity(0.3)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    final path = Path();
    final waveHeight = size.height * 0.3;
    final centerY = size.height / 2;

    for (int i = 0; i < size.width; i += 4) {
      final progress = i / size.width;
      final animatedProgress = (progress + animation.value) % 1.0;
      final amplitude = math.sin(animatedProgress * math.pi * 4) * waveHeight;

      if (i == 0) {
        path.moveTo(i.toDouble(), centerY + amplitude);
      } else {
        path.lineTo(i.toDouble(), centerY + amplitude);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AnimatedWaveform extends StatefulWidget {
  final bool isDarkMode;
  final double height;

  const AnimatedWaveform({
    super.key,
    required this.isDarkMode,
    this.height = 60,
  });

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: WaveformPainter(
            animation: _animation,
            isDarkMode: widget.isDarkMode,
          ),
        );
      },
    );
  }
}

class _UploadPageState extends State<UploadPage> with TickerProviderStateMixin {
  bool isLoading = false;
  String selectedModel = '2stems';
  List<SeparatedFile> separationHistory = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? currentlyPlayingUrl;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    loadHistory();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _scaleController.forward();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('separationHistory') ?? [];
    final loadedHistory =
        jsonList
            .map((jsonStr) => SeparatedFile.fromJson(jsonDecode(jsonStr)))
            .toList();
    setState(() {
      separationHistory = loadedHistory;
    });
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
        separationHistory.map((f) => jsonEncode(f.toJson())).toList();
    await prefs.setStringList('separationHistory', jsonList);
  }

  Future<void> uploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        isLoading = true;
      });

      List<SeparatedFile> batchResults = [];

      for (final file in result.files) {
        final fileBytes = file.bytes;
        final fileName = file.name;

        final uri = Uri.parse(
          'http://localhost:8000/upload/?model=$selectedModel',
        );

        final request = http.MultipartRequest('POST', uri)
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              fileBytes!,
              filename: fileName,
            ),
          );

        try {
          final response = await request.send();
          if (response.statusCode == 200) {
            final respStr = await response.stream.bytesToString();
            final jsonResponse = jsonDecode(respStr) as Map<String, dynamic>;

            Map<String, String> stemsUrls = {};
            jsonResponse.forEach((key, value) {
              stemsUrls[key] = value.toString();
            });

            final separatedFile = SeparatedFile(
              originalFileName: fileName,
              stemsUrls: stemsUrls,
            );

            batchResults.add(separatedFile);
          } else {
            debugPrint("Upload failed for $fileName: ${response.statusCode}");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Failed to separate $fileName"),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint("Exception for $fileName: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error uploading $fileName"),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }

      setState(() {
        separationHistory = [...batchResults, ...separationHistory];
        isLoading = false;
      });

      await saveHistory();
    }
  }

  Future<void> playAudio(String url) async {
    try {
      if (currentlyPlayingUrl == url) {
        await _audioPlayer.pause();
        setState(() {
          currentlyPlayingUrl = null;
        });
      } else {
        await _audioPlayer.play(UrlSource(url));
        setState(() {
          currentlyPlayingUrl = url;
        });
      }
    } catch (e) {
      debugPrint("Error playing audio: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Error playing audio"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void downloadFile(String url, String filename) {
    final anchor =
        html.AnchorElement(href: url)
          ..setAttribute("download", filename)
          ..click();
  }

  void shareFile(String url) {
    Share.share(url);
  }

  Widget buildSeparatedFileCard(SeparatedFile file, int index) {
    List<Widget> buttons = [];
    file.stemsUrls.forEach((stemName, url) {
      final isPlaying = currentlyPlayingUrl == url;

      if (!stemName.toLowerCase().contains('lyrics')) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient:
                    isPlaying
                        ? LinearGradient(
                          colors: [Colors.deepPurple, Colors.purpleAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                        : null,
              ),
              child: ElevatedButton.icon(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    key: ValueKey(isPlaying),
                  ),
                ),
                label: Text("${isPlaying ? 'Pause' : 'Play'} $stemName"),
                onPressed: () => playAudio(url),
                style:
                    isPlaying
                        ? ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                        )
                        : null,
              ),
            ),
          ),
        );
      }

      buttons.add(
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text("Download $stemName"),
            onPressed:
                () => downloadFile(
                  url,
                  stemName.toLowerCase().contains('lyrics')
                      ? "${file.originalFileName}_$stemName.txt"
                      : "${file.originalFileName}_$stemName.wav",
                ),
          ),
        ),
      );

      buttons.add(
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share_rounded),
            label: Text("Share $stemName"),
            onPressed: () => shareFile(url),
          ),
        ),
      );
    });

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _fadeAnimation.value) * 50),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: EdgeInsets.only(top: 8, bottom: 8, left: 16, right: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors:
                      widget.isDarkMode
                          ? [
                            Colors.grey[900]!.withOpacity(0.8),
                            Colors.grey[800]!.withOpacity(0.9),
                          ]
                          : [
                            Colors.white.withOpacity(0.9),
                            Colors.grey[50]!.withOpacity(0.8),
                          ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        widget.isDarkMode
                            ? Colors.black.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.deepPurple,
                                  Colors.purpleAccent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.originalFileName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${file.stemsUrls.length} stems separated",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AnimatedWaveform(
                        isDarkMode: widget.isDarkMode,
                        height: 40,
                      ),
                      const SizedBox(height: 20),
                      Wrap(children: buttons),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildHistoryList() {
    if (separationHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.withOpacity(0.1),
                    Colors.purpleAccent.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.library_music_rounded,
                size: 64,
                color: Colors.deepPurple.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No separated files yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Upload audio files to start separating",
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: separationHistory.length,
      itemBuilder: (context, index) {
        final file = separationHistory[index];
        return buildSeparatedFileCard(file, index);
      },
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors:
                widget.isDarkMode
                    ? [Colors.grey[900]!, Colors.black]
                    : [Colors.grey[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text(
                  "Music Separator",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: AnimatedWaveform(isDarkMode: false, height: 120),
                ),
              ),
              actions: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: IconButton(
                    key: ValueKey(widget.isDarkMode),
                    icon: Icon(
                      widget.isDarkMode
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                    ),
                    onPressed: widget.onToggleTheme,
                    tooltip: widget.isDarkMode ? 'Light Mode' : 'Dark Mode',
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors:
                              widget.isDarkMode
                                  ? [
                                    Colors.grey[800]!.withOpacity(0.8),
                                    Colors.grey[900]!.withOpacity(0.9),
                                  ]
                                  : [
                                    Colors.white.withOpacity(0.9),
                                    Colors.grey[50]!.withOpacity(0.8),
                                  ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color:
                                widget.isDarkMode
                                    ? Colors.black.withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.deepPurple.withOpacity(0.1),
                                      Colors.purpleAccent.withOpacity(0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "Select Model:",
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.deepPurple.withOpacity(0.3),
                                  ),
                                ),
                                child: DropdownButton<String>(
                                  value: selectedModel,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: '2stems',
                                      child: Text('2 Stems'),
                                    ),
                                    DropdownMenuItem(
                                      value: '4stems',
                                      child: Text('4 Stems'),
                                    ),
                                    DropdownMenuItem(
                                      value: '5stems',
                                      child: Text('5 Stems'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        selectedModel = value;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient:
                                  isLoading
                                      ? LinearGradient(
                                        colors: [
                                          Colors.grey,
                                          Colors.grey[400]!,
                                        ],
                                      )
                                      : LinearGradient(
                                        colors: [
                                          Colors.deepPurple,
                                          Colors.purpleAccent,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.deepPurple.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: isLoading ? null : uploadFiles,
                              icon:
                                  isLoading
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                      : const Icon(
                                        Icons.upload_file_rounded,
                                        size: 24,
                                      ),
                              label: Text(
                                isLoading
                                    ? "Processing..."
                                    : "Upload Audio Files",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: buildHistoryList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
