import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

enum SeparatorState { selectSong, uploading, processing, mixerView, volumeAdjust }

class MusicSeparatorScreen extends StatefulWidget {
  final bool isDarkMode;

  const MusicSeparatorScreen({super.key, required this.isDarkMode});

  @override
  State<MusicSeparatorScreen> createState() => MusicSeparatorScreenState();
}

class MusicSeparatorScreenState extends State<MusicSeparatorScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<SongModel> _songs = [];
  bool _hasPermission = false;
  
  SeparatorState _currentState = SeparatorState.selectSong;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  
  String _statusMessage = "";
  String? _taskId;
  int _progress = 0;
  
  // Mixer State
  final List<String> _mixerOptions = [
    'Play / Pause',
    'Vocals Volume: 100%',
    'Music Volume: 100%',
    'Download Vocals',
    'Download Music',
    'Back to Selection'
  ];
  
  double _vocalsVolume = 1.0;
  double _musicVolume = 1.0;
  
  final AudioPlayer _vocalsPlayer = AudioPlayer();
  final AudioPlayer _musicPlayer = AudioPlayer();
  bool _isPlaying = false;
  
  String? _vocalsPath;
  String? _musicPath;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _vocalsPlayer.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    bool permissionStatus = await _audioQuery.permissionsStatus();
    if (!permissionStatus) {
      permissionStatus = await _audioQuery.permissionsRequest();
    }
    setState(() {
      _hasPermission = permissionStatus;
    });
    if (_hasPermission) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    List<SongModel> songs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    if (mounted) {
      setState(() {
        _songs = songs;
      });
    }
  }

  void moveSelection(int delta) {
    if (_currentState == SeparatorState.volumeAdjust) {
      setState(() {
        if (_selectedIndex == 1) {
          _vocalsVolume = (_vocalsVolume + (delta * 0.1)).clamp(0.0, 1.0);
          _vocalsPlayer.setVolume(_vocalsVolume);
          _mixerOptions[1] = 'Vocals Volume: ${(_vocalsVolume * 100).toInt()}%';
        } else if (_selectedIndex == 2) {
          _musicVolume = (_musicVolume + (delta * 0.1)).clamp(0.0, 1.0);
          _musicPlayer.setVolume(_musicVolume);
          _mixerOptions[2] = 'Music Volume: ${(_musicVolume * 100).toInt()}%';
        }
      });
      return;
    }

    setState(() {
      int maxItems = 0;
      if (_currentState == SeparatorState.selectSong) {
        maxItems = _songs.length;
      } else if (_currentState == SeparatorState.mixerView) {
        maxItems = _mixerOptions.length;
      }
      
      if (maxItems == 0) return;

      _selectedIndex += delta;
      if (_selectedIndex >= maxItems) _selectedIndex = 0;
      if (_selectedIndex < 0) _selectedIndex = maxItems - 1;

      if (_scrollController.hasClients) {
        double itemHeight = 40.0;
        double viewportHeight = _scrollController.position.viewportDimension;
        double currentScroll = _scrollController.offset;
        double itemTop = _selectedIndex * itemHeight;
        double itemBottom = itemTop + itemHeight;

        if (itemTop < currentScroll) {
          _scrollController.animateTo(itemTop, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
        } else if (itemBottom > currentScroll + viewportHeight) {
          _scrollController.animateTo(itemBottom - viewportHeight, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
        }
      }
    });
  }

  Future<void> handleCenterClick() async {
    if (_currentState == SeparatorState.volumeAdjust) {
      // Confirm volume adjustment and go back to menu
      setState(() {
        _currentState = SeparatorState.mixerView;
      });
      return;
    }

    if (_currentState == SeparatorState.selectSong && _songs.isNotEmpty) {
      final selectedSong = _songs[_selectedIndex];
      _uploadSong(selectedSong.data);
    } else if (_currentState == SeparatorState.mixerView) {
      if (_selectedIndex == 0) { // Play/Pause
        if (_isPlaying) {
          _vocalsPlayer.pause();
          _musicPlayer.pause();
        } else {
          _vocalsPlayer.play();
          _musicPlayer.play();
        }
        setState(() {
          _isPlaying = !_isPlaying;
        });
      } else if (_selectedIndex == 1 || _selectedIndex == 2) { // Volumes
        setState(() {
          _currentState = SeparatorState.volumeAdjust;
        });
      } else if (_selectedIndex == 3) { // Download Vocals
        _downloadFileToDevice(_vocalsPath, "vocals");
      } else if (_selectedIndex == 4) { // Download Music
        _downloadFileToDevice(_musicPath, "accompaniment");
      } else if (_selectedIndex == 5) { // Back
        _vocalsPlayer.stop();
        _musicPlayer.stop();
        setState(() {
          _isPlaying = false;
          _currentState = SeparatorState.selectSong;
          _selectedIndex = 0;
        });
      }
    }
  }

  Future<void> _uploadSong(String filePath) async {
    setState(() {
      _currentState = SeparatorState.uploading;
      _statusMessage = "Uploading track...";
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('http://127.0.0.1:8000/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      var response = await request.send();
      
      if (response.statusCode == 200) {
        var respData = await response.stream.bytesToString();
        var jsonResponse = json.decode(respData);
        _taskId = jsonResponse['task_id'];
        
        setState(() {
          _currentState = SeparatorState.processing;
          _statusMessage = "Processing with AI...\nThis may take a minute.";
        });
        
        _pollStatus();
      } else {
        setState(() {
          _currentState = SeparatorState.selectSong;
          _statusMessage = "Upload failed.";
        });
      }
    } catch (e) {
      setState(() {
        _currentState = SeparatorState.selectSong;
        _statusMessage = "Network error. Is backend running?";
      });
    }
  }

  Future<void> _pollStatus() async {
    if (_taskId == null) return;
    
    bool isDone = false;
    while (!isDone) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      
      try {
        var response = await http.get(Uri.parse('http://127.0.0.1:8000/status/$_taskId'));
        if (response.statusCode == 200) {
          var data = json.decode(response.body);
          if (data['status'] == 'completed') {
            isDone = true;
            _downloadStemsForPlayback();
          } else if (data['status'] == 'processing' || data['status'] == 'queued') {
            setState(() {
              _progress = data['progress'] ?? 0;
            });
          } else if (data['status'] == 'failed') {
            setState(() {
              _currentState = SeparatorState.selectSong;
              _statusMessage = "Processing failed.";
            });
            return;
          }
        }
      } catch (e) {
        // Retry
      }
    }
  }

  Future<void> _downloadStemsForPlayback() async {
    setState(() {
      _statusMessage = "Downloading stems...";
    });
    
    try {
      Directory tempDir = await getTemporaryDirectory();
      _vocalsPath = '${tempDir.path}/${_taskId}_vocals.mp3';
      _musicPath = '${tempDir.path}/${_taskId}_music.mp3';
      
      var vocalsResp = await http.get(Uri.parse('http://127.0.0.1:8000/download/$_taskId/vocals'));
      File(_vocalsPath!).writeAsBytesSync(vocalsResp.bodyBytes);
      
      var musicResp = await http.get(Uri.parse('http://127.0.0.1:8000/download/$_taskId/accompaniment'));
      File(_musicPath!).writeAsBytesSync(musicResp.bodyBytes);
      
      await _vocalsPlayer.setFilePath(_vocalsPath!);
      await _musicPlayer.setFilePath(_musicPath!);
      
      setState(() {
        _currentState = SeparatorState.mixerView;
        _selectedIndex = 0;
      });
    } catch (e) {
      setState(() {
        _currentState = SeparatorState.selectSong;
        _statusMessage = "Failed to download stems.";
      });
    }
  }

  Future<void> _downloadFileToDevice(String? tempPath, String type) async {
    if (tempPath == null) return;
    try {
      Directory? downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir = await getExternalStorageDirectory();
      }
      
      String newPath = '${downloadsDir!.path}/separated_$type.mp3';
      File(tempPath).copySync(newPath);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Downloads: separated_$type.mp3')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentState == SeparatorState.uploading || _currentState == SeparatorState.processing) {
      bool isProcessing = _currentState == SeparatorState.processing;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isProcessing)
              CircularProgressIndicator(color: widget.isDarkMode ? Colors.white : Colors.black),
            if (isProcessing)
              Container(
                width: 200,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.isDarkMode ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                  border: Border.all(color: widget.isDarkMode ? Colors.white54 : Colors.black54, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      LinearProgressIndicator(
                        value: _progress / 100.0,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF3871D0)
                        ),
                        minHeight: 24,
                      ),
                      Center(
                        child: Text(
                          '$_progress%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Helvetica',
                            shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white : Colors.black,
                fontFamily: 'Helvetica',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_currentState == SeparatorState.mixerView || _currentState == SeparatorState.volumeAdjust) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.isDarkMode ? const [Color(0xFF333333), Color(0xFF111111)] : const [Color(0xFFF8F8F8), Color(0xFFC0C0C0)],
              ),
              border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.black26)),
            ),
            child: Text(
              _currentState == SeparatorState.volumeAdjust ? 'Adjust Volume' : 'Studio Mixer',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Helvetica',
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: widget.isDarkMode ? const Color(0xFF121212) : Colors.white,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _mixerOptions.length,
                itemBuilder: (context, index) {
                  bool isSelected = index == _selectedIndex;
                  bool isBlinking = isSelected && _currentState == SeparatorState.volumeAdjust;
                  
                  return Container(
                    height: 40,
                    decoration: isSelected
                        ? BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: widget.isDarkMode ? const [Color(0xFF0A84FF), Color(0xFF0055B3)] : const [Color(0xFF67A4F2), Color(0xFF3871D0)],
                            ),
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _mixerOptions[index] + (isBlinking ? ' <->' : ''),
                      style: TextStyle(
                        color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Helvetica',
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    // Select Song View
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.isDarkMode ? const [Color(0xFF333333), Color(0xFF111111)] : const [Color(0xFFF8F8F8), Color(0xFFC0C0C0)],
            ),
            border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.black26)),
          ),
          child: Text(
            'Select Song to Separate',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.isDarkMode ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontFamily: 'Helvetica',
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Container(
            color: widget.isDarkMode ? const Color(0xFF121212) : Colors.white,
            child: _hasPermission
                ? (_songs.isEmpty
                    ? const Center(child: Text("No songs found"))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _songs.length,
                        itemBuilder: (context, index) {
                          bool isSelected = index == _selectedIndex;
                          var song = _songs[index];
                          return Container(
                            height: 40,
                            decoration: isSelected
                                ? BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: widget.isDarkMode ? const [Color(0xFF0A84FF), Color(0xFF0055B3)] : const [Color(0xFF67A4F2), Color(0xFF3871D0)],
                                    ),
                                  )
                                : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black),
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Helvetica',
                                fontSize: 14,
                              ),
                            ),
                          );
                        },
                      ))
                : const Center(child: Text("Need storage permission")),
          ),
        ),
      ],
    );
  }
}
