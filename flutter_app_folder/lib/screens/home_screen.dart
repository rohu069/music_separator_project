import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audius_service.dart';

import 'playlists_screen.dart';
import 'favorites_screen.dart';
import 'music_separator_screen.dart';
import 'search_screen.dart';
import 'local_songs_screen.dart';
import 'package:on_audio_query/on_audio_query.dart';

enum IpodScreenState { home, menu, playlists, favorites, musicSeparator, search, localSongs }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  IpodScreenState _currentScreen = IpodScreenState.home;
  IpodScreenState? _previousScreen;
  int _selectedIndex = 0;
  bool _isDarkMode = false;
  bool _isLocalMode = false;
  
  bool _showTrackOptions = false;
  int _trackOptionsIndex = 0;
  bool _isCurrentTrackFavorite = false;

  bool _showPlaylistSelector = false;
  int _playlistSelectorIndex = 0;
  List<String> _existingPlaylists = [];

  bool _showPlaylistKeyboard = false;
  String _newPlaylistName = '';
  int _keyboardIndex = 0;
  final String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _<*";

  String? _playingContext;

  // Variables for circular scrolling
  double _lastAngle = 0.0;
  double _accumulatedAngle = 0.0;
  final double _scrollThreshold = pi / 4; // 45 degrees for one tick

  // Audius & Player State
  final AudiusService _audiusService = AudiusService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Track? _currentTrack;
  bool _isPlaying = false;
  bool _isLoading = false;
  List<Track> _trackQueue = [];
  List<AudioSource>? _playlist;
  Timer? _seekTimer;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();
  final GlobalKey<FavoritesScreenState> _favoritesKey = GlobalKey<FavoritesScreenState>();
  final GlobalKey<PlaylistsScreenState> _playlistsKey = GlobalKey<PlaylistsScreenState>();
  final GlobalKey<LocalSongsScreenState> _localSongsKey = GlobalKey<LocalSongsScreenState>();
  final GlobalKey<MusicSeparatorScreenState> _separatorKey = GlobalKey<MusicSeparatorScreenState>();

  final ScrollController _menuScrollController = ScrollController();
  int? _pressedSector;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAudioPlayer();
    _loadInitialTrack();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      });
    }
  }

  void _initAudioPlayer() {
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          bool isLocal = _currentTrack?.isLocal == true;
          _isLoading = !isLocal && (state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering);
        });
        if (state.processingState == ProcessingState.completed) {
          _skipNext();
        }
      }
    });
    _audioPlayer.currentIndexStream.listen((index) {
      if (mounted && index != null && _trackQueue.isNotEmpty) {
        setState(() {
          _currentTrack = _trackQueue[index];
        });
      }
    });
    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });
  }

  Future<void> _fetchQueue({bool setSource = true}) async {
    if (_trackQueue.isEmpty) {
      _trackQueue = await _audiusService.getTrendingTracks();
      _trackQueue.shuffle();
      
      final audioSources = <AudioSource>[];
      for (var track in _trackQueue) {
        final streamUrl = await _audiusService.getStreamUrl(track.id);
        audioSources.add(AudioSource.uri(Uri.parse(streamUrl)));
      }
      _playlist = audioSources;
      if (setSource && _playlist!.isNotEmpty) {
        await _audioPlayer.setAudioSources(_playlist!, initialIndex: 0);
        await _audioPlayer.setLoopMode(LoopMode.all);
      }
    }
  }

  Future<void> _loadInitialTrack() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final lastTrackStr = prefs.getString('last_track');
    final lastPositionMs = prefs.getInt('last_position') ?? 0;
    final lastQueueStr = prefs.getString('last_queue');
    final lastContextStr = prefs.getString('last_context');

    if (lastContextStr != null) {
      _playingContext = lastContextStr;
    }

    if (lastQueueStr != null) {
      try {
        final List<dynamic> queueList = json.decode(lastQueueStr);
        _trackQueue = queueList.map((j) => Track.fromLocalJson(j)).toList();
      } catch (e) {
        // Fallback
      }
    }

    if (_trackQueue.isEmpty) {
      await _fetchQueue(setSource: false);
    } else {
      final host = await _audiusService.getHostNode();
      List<AudioSource> audioSources = [];
      for (var t in _trackQueue) {
        if (t.isLocal && t.localPath != null) {
          audioSources.add(AudioSource.uri(Uri.file(t.localPath!)));
        } else {
          audioSources.add(AudioSource.uri(Uri.parse('$host/v1/tracks/${t.id}/stream?app_name=${_audiusService.appName}')));
        }
      }
      _playlist = audioSources;
    }

    if (lastTrackStr != null) {
      try {
        final lastTrack = Track.fromLocalJson(json.decode(lastTrackStr));
        if (mounted) {
          setState(() {
            _currentTrack = lastTrack;
            _currentPosition = Duration(milliseconds: lastPositionMs);
            _isLocalMode = lastTrack.isLocal;
          });
        }
        
        int initialIndex = _trackQueue.indexWhere((t) => t.id == lastTrack.id);
        if (initialIndex == -1) {
          _trackQueue.insert(0, lastTrack);
          initialIndex = 0;
          if (lastTrack.isLocal && lastTrack.localPath != null) {
            _playlist!.insert(0, AudioSource.uri(Uri.file(lastTrack.localPath!)));
          } else {
            final host = await _audiusService.getHostNode();
            _playlist!.insert(0, AudioSource.uri(Uri.parse('$host/v1/tracks/${lastTrack.id}/stream?app_name=${_audiusService.appName}')));
          }
        }
        
        await _audioPlayer.setAudioSources(
          _playlist!,
          initialIndex: initialIndex,
          initialPosition: Duration(milliseconds: lastPositionMs),
        );
        await _audioPlayer.setLoopMode(LoopMode.all);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } catch (e) {
        if (_trackQueue.isNotEmpty && mounted) {
          setState(() {
            _currentTrack = _trackQueue[0];
            _isLoading = false;
          });
          await _audioPlayer.setAudioSources(_playlist!, initialIndex: 0);
          await _audioPlayer.setLoopMode(LoopMode.all);
        }
      }
    } else {
      if (_trackQueue.isNotEmpty) {
        if (mounted) {
          setState(() {
            _currentTrack = _trackQueue[0];
            _isLoading = false;
          });
        }
        await _audioPlayer.setAudioSources(_playlist!, initialIndex: 0);
        await _audioPlayer.setLoopMode(LoopMode.all);
      }
    }
  }

  Future<void> _loadOnlineSongs() async {
    setState(() {
      _isLoading = true;
      _trackQueue.clear();
      _isLocalMode = false;
    });
    
    try {
      await _fetchQueue(setSource: true);
    } catch (e) {
      debugPrint("Error fetching online songs: $e");
    }
    
    if (_trackQueue.isNotEmpty && mounted) {
      setState(() {
        _currentTrack = _trackQueue[0];
        _isLoading = false;
        _currentPosition = Duration.zero;
      });
      _audioPlayer.play();
      _saveCurrentTrack();
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load online songs. Please check your internet connection.')),
      );
    }
  }

  Future<void> _playTrackNow(List<Track> tracks, int startIndex, [String? playlistContext]) async {
    if (_currentScreen != IpodScreenState.home) {
      _previousScreen = _currentScreen;
    }
    final track = tracks[startIndex];
    setState(() {
      _playingContext = playlistContext;
      _currentScreen = IpodScreenState.home;
      if (!track.isLocal) {
        _isLoading = true;
      }
      _currentTrack = track;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    });

    try {
      final host = await _audiusService.getHostNode();
      
      List<AudioSource> audioSources = [];
      for (var t in tracks) {
        if (t.isLocal && t.localPath != null) {
          audioSources.add(AudioSource.uri(Uri.file(t.localPath!)));
        } else {
          audioSources.add(AudioSource.uri(Uri.parse('$host/v1/tracks/${t.id}/stream?app_name=${_audiusService.appName}')));
        }
      }

      _trackQueue = List.from(tracks);
      _playlist = audioSources;
      
      await _audioPlayer.setAudioSources(audioSources, initialIndex: startIndex);
      await _audioPlayer.setLoopMode(LoopMode.all);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to play track. Please try again.')),
        );
      }
    }
  }

  Future<void> _saveCurrentTrack() async {
    if (_currentTrack != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_track', json.encode(_currentTrack!.toJson()));
      await prefs.setInt('last_position', _currentPosition.inMilliseconds);
      if (_trackQueue.isNotEmpty) {
        final queueJson = json.encode(_trackQueue.map((t) => t.toJson()).toList());
        await prefs.setString('last_queue', queueJson);
      }
      if (_playingContext != null) {
        await prefs.setString('last_context', _playingContext!);
      } else {
        await prefs.remove('last_context');
      }
    }
  }

  void _togglePlayPause() {
    Vibration.vibrate(duration: 40);
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
      _saveCurrentTrack();
    }
  }

  void _skipNext() {
    Vibration.vibrate(duration: 40);
    _audioPlayer.seekToNext();
    _saveCurrentTrack();
  }

  void _skipPrevious() {
    Vibration.vibrate(duration: 40);
    if (_audioPlayer.position.inSeconds > 3) {
      _audioPlayer.seek(Duration.zero);
    } else {
      _audioPlayer.seekToPrevious();
    }
    _saveCurrentTrack();
  }

  void _startSeeking(int direction) {
    _seekTimer?.cancel();
    _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_totalDuration.inMilliseconds > 0) {
        Vibration.vibrate(duration: 10);
        int newPositionMs = _currentPosition.inMilliseconds + (direction * 3000);
        newPositionMs = newPositionMs.clamp(0, _totalDuration.inMilliseconds);
        _audioPlayer.seek(Duration(milliseconds: newPositionMs));
      }
    });
  }

  void _stopSeeking() {
    _seekTimer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seekTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _saveCurrentTrack();
    }
  }

  Widget _buildTrackOptionsOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          border: Border(top: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26, width: 2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, -2))
          ]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isDarkMode ? const [Color(0xFF444444), Color(0xFF222222)] : const [Color(0xFFE0E0E0), Color(0xFFA0A0A0)],
                ),
                border: Border(bottom: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
              ),
              child: Text(
                'Options',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Helvetica',
                  fontSize: 12,
                ),
              ),
            ),
            _buildOptionItem(_isCurrentTrackFavorite ? 'Remove from Favorites' : 'Add to Favorites', Icons.favorite, 0),
            _buildOptionItem('Add to Playlist', Icons.queue_music, 1),
            if (_playingContext != null && _playingContext != 'Favorites')
              _buildOptionItem('Remove from $_playingContext', Icons.remove_circle_outline, 2),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSelectorOverlay() {
    return Positioned.fill(
      child: Container(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isDarkMode ? const [Color(0xFF444444), Color(0xFF222222)] : const [Color(0xFFE0E0E0), Color(0xFFA0A0A0)],
                ),
                border: Border(bottom: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
              ),
              child: Text(
                'Select Playlist',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Helvetica',
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _existingPlaylists.length + 1,
                itemBuilder: (context, index) {
                  bool isSelected = index == _playlistSelectorIndex;
                  String title = index == 0 ? '[Create New Playlist]' : _existingPlaylists[index - 1];
                  IconData icon = index == 0 ? Icons.add : Icons.queue_music;
                  
                  return Container(
                    decoration: isSelected
                        ? BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _isDarkMode ? const [Color(0xFF0A84FF), Color(0xFF0055B3)] : const [Color(0xFF67A4F2), Color(0xFF3871D0)],
                            ),
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? Colors.white : (_isDarkMode ? Colors.white54 : Colors.black87),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : (_isDarkMode ? Colors.white : Colors.black),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Helvetica',
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistKeyboardOverlay() {
    return Positioned.fill(
      child: Container(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isDarkMode ? const [Color(0xFF444444), Color(0xFF222222)] : const [Color(0xFFE0E0E0), Color(0xFFA0A0A0)],
                ),
                border: Border(bottom: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
              ),
              child: Text(
                'New Playlist Name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Helvetica',
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  _newPlaylistName.isEmpty ? "Type name..." : _newPlaylistName,
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white : Colors.black,
                    fontFamily: 'Helvetica',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Alphabet Strip
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: _isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFD4D4D4),
                border: Border(top: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(7, (i) {
                  int index = (_keyboardIndex + (i - 3)) % _alphabet.length;
                  if (index < 0) index += _alphabet.length;
                  bool isSelected = i == 3;
                  String char = _alphabet[index];
                  String display = char == '_' ? 'SP' : char == '<' ? 'DEL' : char == '*' ? 'OK' : char;
                  
                  return Container(
                    width: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? (_isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      display,
                      style: TextStyle(
                        color: isSelected ? Colors.white : (_isDarkMode ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontFamily: 'Helvetica',
                        fontSize: 16,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem(String title, IconData icon, int index) {
    bool isSelected = index == _trackOptionsIndex;
    return Container(
      decoration: isSelected
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isDarkMode ? const [Color(0xFF0A84FF), Color(0xFF0055B3)] : const [Color(0xFF67A4F2), Color(0xFF3871D0)],
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? Colors.white : (_isDarkMode ? Colors.white54 : Colors.black87),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : (_isDarkMode ? Colors.white : Colors.black),
              fontWeight: FontWeight.bold,
              fontFamily: 'Helvetica',
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(Track track) async {
    setState(() => _showTrackOptions = false);
    final prefs = await SharedPreferences.getInstance();
    List<String> favs = prefs.getStringList('favorites_list') ?? [];
    
    if (_isCurrentTrackFavorite) {
      favs.removeWhere((jsonStr) => json.decode(jsonStr)['id'].toString() == track.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Favorites')));
    } else {
      favs.add(json.encode(track.toJson()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Favorites')));
    }
    await prefs.setStringList('favorites_list', favs);
  }

  Future<void> _openPlaylistSelector() async {
    setState(() {
      _showTrackOptions = false;
    });
    final prefs = await SharedPreferences.getInstance();
    String? playlistsDataStr = prefs.getString('playlists_data');
    Map<String, dynamic> playlistsData = {};
    if (playlistsDataStr != null) {
      try {
        playlistsData = json.decode(playlistsDataStr);
      } catch (e) {
        debugPrint('Error decoding playlists: $e');
      }
    }
    setState(() {
      _existingPlaylists = playlistsData.keys.toList();
      _playlistSelectorIndex = 0;
      _showPlaylistSelector = true;
    });
  }

  void _handlePlaylistSelect() {
    if (_playlistSelectorIndex == 0) {
      // Create New Playlist
      setState(() {
        _showPlaylistSelector = false;
        _showPlaylistKeyboard = true;
        _newPlaylistName = '';
        _keyboardIndex = 0;
      });
    } else {
      // Add to existing playlist
      String selectedPlaylist = _existingPlaylists[_playlistSelectorIndex - 1];
      _addToSpecificPlaylist(_currentTrack!, selectedPlaylist);
      setState(() {
        _showPlaylistSelector = false;
      });
    }
  }

  void _handleKeyboardSelect() {
    setState(() {
      final selectedChar = _alphabet[_keyboardIndex];
      if (selectedChar == '<') {
        if (_newPlaylistName.isNotEmpty) {
          _newPlaylistName = _newPlaylistName.substring(0, _newPlaylistName.length - 1);
        }
      } else if (selectedChar == '_') {
        _newPlaylistName += ' ';
      } else if (selectedChar == '*') {
        if (_newPlaylistName.isNotEmpty) {
          String newName = _newPlaylistName.trim();
          _showPlaylistKeyboard = false;
          _addToSpecificPlaylist(_currentTrack!, newName);
        }
      } else {
        _newPlaylistName += selectedChar;
      }
    });
  }

  Future<void> _addToSpecificPlaylist(Track track, String playlistName) async {
    final prefs = await SharedPreferences.getInstance();
    String? playlistsDataStr = prefs.getString('playlists_data');
    Map<String, dynamic> playlistsData = {};
    if (playlistsDataStr != null) {
      try {
        playlistsData = json.decode(playlistsDataStr);
      } catch (e) {
        debugPrint('Error decoding playlists: $e');
      }
    }
    
    List<dynamic> trackList = playlistsData[playlistName] ?? [];
    trackList.add(json.encode(track.toJson()));
    playlistsData[playlistName] = trackList;
    
    await prefs.setString('playlists_data', json.encode(playlistsData));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to $playlistName')));
    }
  }

  Future<void> _removeFromPlaylist(Track track, String playlistName) async {
    setState(() => _showTrackOptions = false);
    final prefs = await SharedPreferences.getInstance();
    String? playlistsDataStr = prefs.getString('playlists_data');
    Map<String, dynamic> playlistsData = {};
    if (playlistsDataStr != null) {
      try {
        playlistsData = json.decode(playlistsDataStr);
      } catch (e) {
        debugPrint('Error decoding playlists: $e');
      }
    }
    
    List<dynamic> trackList = playlistsData[playlistName] ?? [];
    trackList.removeWhere((jsonStr) => json.decode(jsonStr)['id'].toString() == track.id.toString());
    playlistsData[playlistName] = trackList;
    
    await prefs.setString('playlists_data', json.encode(playlistsData));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed from $playlistName')));
    }
  }

  List<Map<String, dynamic>> get _menuItems {
    return [
      {'title': 'Now Playing', 'icon': Icons.play_circle_outline},
      {'title': 'Search', 'icon': Icons.search},
      {'title': _isLocalMode ? 'Online Songs' : 'Your Songs', 'icon': _isLocalMode ? Icons.cloud : Icons.library_music},
      {'title': 'Playlists', 'icon': Icons.queue_music},
      {'title': 'Favorites', 'icon': Icons.favorite},
      {'title': 'Music Separator', 'icon': Icons.graphic_eq},
      {'title': _isDarkMode ? 'Light Mode' : 'Dark Mode', 'icon': Icons.brightness_6},
    ];
  }

  void _handleMenuSelection() {
    String selectedTitle = _menuItems[_selectedIndex]['title'];
    
    if (selectedTitle == 'Now Playing') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.home;
      });
    } else if (selectedTitle == 'Search') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.search;
      });
    } else if (selectedTitle == 'Online Songs') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.home;
        _selectedIndex = 0;
        _playingContext = null;
        _trackQueue.clear();
        _isLocalMode = false;
      });
      _loadOnlineSongs();
    } else if (selectedTitle == 'Your Songs') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.localSongs;
        _isLocalMode = true;
      });
    } else if (selectedTitle == 'Playlists') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.playlists;
      });
    } else if (selectedTitle == 'Favorites') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.favorites;
      });
    } else if (selectedTitle == 'Music Separator') {
      setState(() {
        _previousScreen = null;
        _currentScreen = IpodScreenState.musicSeparator;
      });
    } else if (selectedTitle == 'Dark Mode' || selectedTitle == 'Light Mode') {
      setState(() {
        _isDarkMode = !_isDarkMode;
      });
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('isDarkMode', _isDarkMode);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected: $selectedTitle'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _toggleMenu() {
    Vibration.vibrate(duration: 30);
    if (_showPlaylistKeyboard) {
      setState(() => _showPlaylistKeyboard = false);
      return;
    }
    if (_showPlaylistSelector) {
      setState(() => _showPlaylistSelector = false);
      return;
    }
    if (_showTrackOptions) {
      setState(() {
        _showTrackOptions = false;
      });
      return;
    }
    
    if (_currentScreen == IpodScreenState.home && _previousScreen != null) {
      setState(() {
        _currentScreen = _previousScreen!;
        _previousScreen = null;
      });
      return;
    }
    
    setState(() {
      if (_currentScreen == IpodScreenState.menu) {
        _currentScreen = IpodScreenState.home;
        _previousScreen = null;
      } else {
        _previousScreen = _currentScreen;
        _currentScreen = IpodScreenState.menu;
      }
    });
  }

  void _moveSelection(int delta) {
    if (_showPlaylistKeyboard) {
      setState(() {
        _keyboardIndex = (_keyboardIndex + delta) % _alphabet.length;
        if (_keyboardIndex < 0) _keyboardIndex += _alphabet.length;
      });
      return;
    }
    if (_showPlaylistSelector) {
      int newIndex = _playlistSelectorIndex + delta;
      int maxItems = _existingPlaylists.length + 1; // +1 for Create New Playlist
      if (newIndex >= maxItems) newIndex = 0;
      if (newIndex < 0) newIndex = maxItems - 1;
      if (newIndex != _playlistSelectorIndex) {
        Vibration.vibrate(duration: 15);
        setState(() {
          _playlistSelectorIndex = newIndex;
        });
      }
      return;
    }
    if (_showTrackOptions) {
      int maxIndex = (_playingContext != null && _playingContext != 'Favorites') ? 2 : 1;
      int newIndex = _trackOptionsIndex + delta;
      if (newIndex > maxIndex) newIndex = 0;
      if (newIndex < 0) newIndex = maxIndex;
      if (newIndex != _trackOptionsIndex) {
        Vibration.vibrate(duration: 15);
        setState(() {
          _trackOptionsIndex = newIndex;
        });
      }
      return;
    }
    if (_currentScreen == IpodScreenState.menu) {
      int newIndex = _selectedIndex + delta;
      if (newIndex >= _menuItems.length) {
        newIndex = 0;
      } else if (newIndex < 0) {
        newIndex = _menuItems.length - 1;
      }
      
      if (newIndex != _selectedIndex) {
        Vibration.vibrate(duration: 15);
        setState(() {
          _selectedIndex = newIndex;
        });

        if (_menuScrollController.hasClients) {
          double itemHeight = 30.0;
          double viewportHeight = _menuScrollController.position.viewportDimension;
          double currentScroll = _menuScrollController.offset;
          double itemTop = newIndex * itemHeight;
          double itemBottom = itemTop + itemHeight;
          
          if (itemTop < currentScroll) {
            _menuScrollController.animateTo(itemTop, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
          } else if (itemBottom > currentScroll + viewportHeight) {
            _menuScrollController.animateTo(itemBottom - viewportHeight, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
          }
        }
      }
    } else if (_currentScreen == IpodScreenState.search) {
      Vibration.vibrate(duration: 15);
      _searchKey.currentState?.moveSelection(delta);
    } else if (_currentScreen == IpodScreenState.favorites) {
      Vibration.vibrate(duration: 15);
      _favoritesKey.currentState?.moveSelection(delta);
    } else if (_currentScreen == IpodScreenState.playlists) {
      Vibration.vibrate(duration: 15);
      _playlistsKey.currentState?.moveSelection(delta);
    } else if (_currentScreen == IpodScreenState.localSongs) {
      Vibration.vibrate(duration: 15);
      _localSongsKey.currentState?.moveSelection(delta);
    } else if (_currentScreen == IpodScreenState.musicSeparator) {
      Vibration.vibrate(duration: 15);
      _separatorKey.currentState?.moveSelection(delta);
    } else if (_currentScreen == IpodScreenState.home) {
      if (delta > 0) {
        _skipNext();
      } else if (delta < 0) {
        _skipPrevious();
      }
    }
  }

  String _getHeaderText() {
    if (_playingContext == null) return _currentTrack?.isLocal == true ? 'Local Songs' : 'Online Songs';
    if (_playingContext == 'Favorites') return 'From Favorites';
    if (_playingContext == 'Search') return 'From Search';
    return 'Playlist: "$_playingContext"';
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildNowPlayingScreen() {
    if (_currentTrack == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.grey));
    }
    
    return Column(
      children: [
        // Top status bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _isDarkMode ? const [Color(0xFF333333), Color(0xFF111111)] : const [Color(0xFFF8F8F8), Color(0xFFC0C0C0)],
            ),
            border: Border(bottom: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _isLoading 
                ? const SizedBox(
                    width: 14, 
                    height: 14, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)
                  )
                : Icon(
                    _isPlaying ? Icons.play_arrow : Icons.pause,
                    size: 14,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: MarqueeText(
                    text: _getHeaderText(),
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Helvetica',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              Icon(Icons.battery_full, size: 14, color: _isDarkMode ? Colors.white : Colors.black),
            ],
          ),
        ),
        
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Artwork
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, offset: Offset(2, 2), blurRadius: 4),
                    ]
                  ),
                  child: _currentTrack!.isLocal
                      ? QueryArtworkWidget(
                          key: ValueKey(_currentTrack!.id),
                          keepOldArtwork: true,
                          id: int.tryParse(_currentTrack!.id) ?? 0,
                          type: ArtworkType.AUDIO,
                          nullArtworkWidget: Image.asset('assets/images/fallback_album_cover.png', fit: BoxFit.cover),
                          artworkFit: BoxFit.cover,
                          artworkWidth: 100,
                          artworkHeight: 100,
                        )
                      : _currentTrack!.artworkUrl != null
                          ? Image.network(
                              _currentTrack!.artworkUrl!, 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset('assets/images/fallback_album_cover.png', fit: BoxFit.cover);
                              },
                            )
                          : Image.asset('assets/images/fallback_album_cover.png', fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                // Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentTrack!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isDarkMode ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Helvetica',
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentTrack!.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isDarkMode ? Colors.white54 : Colors.black54,
                          fontFamily: 'Helvetica',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                _formatDuration(_currentPosition),
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black, fontSize: 10, fontFamily: 'Helvetica'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: _totalDuration.inMilliseconds > 0 
                      ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds 
                      : 0.0,
                  backgroundColor: _isDarkMode ? Colors.white24 : Colors.black26,
                  color: _isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF67A4F2),
                  minHeight: 6,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${_formatDuration(_totalDuration - _currentPosition)}',
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black, fontSize: 10, fontFamily: 'Helvetica'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScreenContent() {
    if (_currentScreen == IpodScreenState.search) {
      return SearchScreen(
        key: _searchKey,
        isDarkMode: _isDarkMode,
        isLocalMode: _isLocalMode,
        onTrackSelected: _playTrackNow,
      );
    } else if (_currentScreen == IpodScreenState.playlists) {
      return PlaylistsScreen(
        key: _playlistsKey,
        isDarkMode: _isDarkMode,
        isLocalMode: _isLocalMode,
        onTrackSelected: _playTrackNow,
      );
    } else if (_currentScreen == IpodScreenState.favorites) {
      return FavoritesScreen(
        key: _favoritesKey,
        isDarkMode: _isDarkMode,
        isLocalMode: _isLocalMode,
        onTrackSelected: _playTrackNow,
      );
    } else if (_currentScreen == IpodScreenState.musicSeparator) {
      return MusicSeparatorScreen(
        key: _separatorKey,
        isDarkMode: _isDarkMode,
      );
    } else if (_currentScreen == IpodScreenState.home) {
      return _buildNowPlayingScreen();
    } else if (_currentScreen == IpodScreenState.localSongs) {
      return LocalSongsScreen(
        key: _localSongsKey,
        isDarkMode: _isDarkMode,
        onTrackSelected: _playTrackNow,
      );
    } else {
      // Classic iPod Menu
      return Column(
        children: [
          // Top Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isDarkMode ? const [Color(0xFF333333), Color(0xFF111111)] : const [Color(0xFFF8F8F8), Color(0xFFC0C0C0)],
              ),
              border: Border(bottom: BorderSide(color: _isDarkMode ? Colors.black : Colors.black26)),
            ),
            child: Text(
              'iPod',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Helvetica',
                fontSize: 14,
              ),
            ),
          ),
          // Menu Items
          Expanded(
            child: Container(
              color: _isDarkMode ? const Color(0xFF121212) : Colors.white,
              child: ListView.builder(
                controller: _menuScrollController,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _menuItems.length,
                itemBuilder: (context, index) {
                  bool isSelected = index == _selectedIndex;
                  return Container(
                      height: 30,
                      decoration: isSelected
                          ? BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _isDarkMode ? const [Color(0xFF0A84FF), Color(0xFF0055B3)] : const [Color(0xFF67A4F2), Color(0xFF3871D0)],
                              ),
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _menuItems[index]['icon'],
                                color: isSelected ? Colors.white : (_isDarkMode ? Colors.white54 : Colors.black87),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _menuItems[index]['title'],
                                style: TextStyle(
                                  color: isSelected ? Colors.white : (_isDarkMode ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Helvetica',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: isSelected ? Colors.white : (_isDarkMode ? Colors.white30 : Colors.black54),
                            size: 20,
                          ),
                        ],
                      ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black, // Fallback
      body: Stack(
        children: [
          // 1. Base Macroscopic Lighting (The cylindrical metal look)
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: _isDarkMode ? const [
                  Color(0xFF050505),
                  Color(0xFF141414),
                  Color(0xFF333333),
                  Color(0xFF1A1A1A),
                  Color(0xFF111111),
                  Color(0xFF1A1A1A),
                  Color(0xFF333333),
                  Color(0xFF141414),
                  Color(0xFF050505),
                ] : const [
                  Color(0xFF7A7A7A), // Dark left edge
                  Color(0xFFB0B0B0),
                  Color(0xFFFDFDFD), // Bright highlight
                  Color(0xFFD4D4D4),
                  Color(0xFFC8C8C8), // Center
                  Color(0xFFD4D4D4),
                  Color(0xFFFDFDFD), // Bright highlight
                  Color(0xFFB0B0B0),
                  Color(0xFF7A7A7A), // Dark right edge
                ],
                stops: const [0.0, 0.08, 0.18, 0.35, 0.5, 0.65, 0.82, 0.92, 1.0],
              ),
            ),
          ),
          // 2. Brushed Metal Texture Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: BrushedMetalPainter(),
            ),
          ),
          // 3. The UI Elements
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                // iPod Screen Area
                Center(
                  child: Container(
                    width: 320,
                    height: 240,
                    decoration: BoxDecoration(
                      color: Colors.black, // Bezel color
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF555555), // Outer chamfer
                        width: 1.5,
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Colors.white60,
                          offset: Offset(0, 1),
                          blurRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          offset: const Offset(0, 5),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12), // Bezel thickness
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isDarkMode ? const Color(0xFF121212) : const Color(0xFFC2D2DC),
                        borderRadius: BorderRadius.circular(4),
                        // Screen inner shadow
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            offset: const Offset(0, 4),
                            blurRadius: 8,
                            spreadRadius: -2,
                            blurStyle: BlurStyle.inner,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: [
                            // Glossy screen reflection
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.4),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // The Screen Content
                            _buildScreenContent(),
                            if (_showTrackOptions)
                              _buildTrackOptionsOverlay(),
                            if (_showPlaylistSelector)
                              _buildPlaylistSelectorOverlay(),
                            if (_showPlaylistKeyboard)
                              _buildPlaylistKeyboardOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Click Wheel
                Center(
                  child: GestureDetector(
                    onPanStart: (details) {
                      // Center of the 280x280 wheel is (140, 140)
                      _lastAngle = atan2(details.localPosition.dy - 140, details.localPosition.dx - 140);
                    },
                    onPanUpdate: (details) {
                      double dx = details.localPosition.dx - 140;
                      double dy = details.localPosition.dy - 140;
                      double distance = sqrt(dx * dx + dy * dy);
                      
                      double currentAngle = atan2(dy, dx);
                      double delta = currentAngle - _lastAngle;

                      // Handle crossing the -pi/pi boundary
                      if (delta > pi) delta -= 2 * pi;
                      if (delta < -pi) delta += 2 * pi;

                      _lastAngle = currentAngle;

                      // Only accumulate scroll if finger is in the outer ring (radius 45 to 140)
                      if (distance >= 45 && distance <= 140) {
                        _accumulatedAngle += delta;

                        // Threshold determines sensitivity of scrolling
                        if (_accumulatedAngle > _scrollThreshold) {
                          _moveSelection(1); // Scroll down
                          _accumulatedAngle = 0.0;
                        } else if (_accumulatedAngle < -_scrollThreshold) {
                          _moveSelection(-1); // Scroll up
                          _accumulatedAngle = 0.0;
                        }
                      } else {
                        // Reset accumulated momentum if they drag into the dead zone
                        _accumulatedAngle = 0.0;
                      }
                    },
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Flat, diffuse gradient for a matte rubber look
                        gradient: RadialGradient(
                          colors: _isDarkMode ? const [
                            Color(0xFF181818), // Flatter, matte rubber look
                            Color(0xFF121212),
                          ] : const [
                            Color(0xFFFAFAFA),
                            Color(0xFFE8E8E8),
                          ],
                          stops: const [0.4, 1.0],
                        ),
                        boxShadow: [
                          // Soft, diffuse outer shadow
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            offset: const Offset(0, 15),
                            blurRadius: 25,
                            spreadRadius: -4,
                          ),
                          // Soft dark inner shadow at the bottom for density
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            offset: const Offset(0, -4),
                            blurRadius: 10,
                            spreadRadius: 1,
                            blurStyle: BlurStyle.inner,
                          ),
                          // Soft diffuse highlight at the top
                          BoxShadow(
                            color: _isDarkMode ? Colors.transparent : Colors.white,
                            offset: const Offset(0, 4),
                            blurRadius: 8,
                            spreadRadius: 1,
                            blurStyle: BlurStyle.inner,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: ClickWheelPainter(
                                pressedSector: _pressedSector,
                                isDarkMode: _isDarkMode,
                              ),
                            ),
                          ),
                        // Menu Text
                        Positioned(
                          top: 15,
                          child: ClickWheelButton(
                            onTap: _toggleMenu,
                            onStateChange: (pressed) => setState(() => _pressedSector = pressed ? 0 : null),
                            child: Container(
                              color: Colors.transparent, // Expand hit area
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'MENU',
                                style: TextStyle(
                                  color: _isDarkMode ? Colors.white : const Color(0xFF909090),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Play/Pause Icon
                        Positioned(
                          bottom: 15,
                          child: ClickWheelButton(
                            onTap: _togglePlayPause,
                            onStateChange: (pressed) => setState(() => _pressedSector = pressed ? 2 : null),
                            child: Container(
                              color: Colors.transparent, // Expand hit area
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow,
                                    size: 26,
                                    color: _isDarkMode ? Colors.white : const Color(0xFF909090),
                                  ),
                                  Icon(
                                    Icons.pause,
                                    size: 24,
                                    color: _isDarkMode ? Colors.white : const Color(0xFF909090),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Backward Icon
                        Positioned(
                          left: 15,
                          child: ClickWheelButton(
                            onTap: _skipPrevious,
                            onStateChange: (pressed) => setState(() => _pressedSector = pressed ? 3 : null),
                            onLongPressStart: (_) => _startSeeking(-1),
                            onLongPressEnd: (_) => _stopSeeking(),
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.all(20),
                              child: Icon(
                                Icons.fast_rewind,
                                size: 28,
                                color: _isDarkMode ? Colors.white : const Color(0xFF909090),
                              ),
                            ),
                          ),
                        ),
                        // Forward Icon
                        Positioned(
                          right: 15,
                          child: ClickWheelButton(
                            onTap: _skipNext,
                            onStateChange: (pressed) => setState(() => _pressedSector = pressed ? 1 : null),
                            onLongPressStart: (_) => _startSeeking(1),
                            onLongPressEnd: (_) => _stopSeeking(),
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.all(20),
                              child: Icon(
                                Icons.fast_forward,
                                size: 28,
                                color: _isDarkMode ? Colors.white : const Color(0xFF909090),
                              ),
                            ),
                          ),
                        ),
                        ClickWheelButton(
                          pressedOpacity: 1.0, // Don't become transparent to hide background
                          onTap: () {
                            Vibration.vibrate(duration: 30);
                            if (_showPlaylistKeyboard) {
                              _handleKeyboardSelect();
                              return;
                            }
                            if (_showPlaylistSelector) {
                              _handlePlaylistSelect();
                              return;
                            }
                            if (_showTrackOptions) {
                              if (_trackOptionsIndex == 0) {
                                _toggleFavorite(_currentTrack!);
                              } else if (_trackOptionsIndex == 1) {
                                _openPlaylistSelector();
                              } else if (_trackOptionsIndex == 2) {
                                _removeFromPlaylist(_currentTrack!, _playingContext!);
                              }
                              return;
                            } else if (_currentScreen == IpodScreenState.menu) {
                              _handleMenuSelection();
                            } else if (_currentScreen == IpodScreenState.search) {
                              _searchKey.currentState?.handleSelect();
                            } else if (_currentScreen == IpodScreenState.favorites) {
                              _favoritesKey.currentState?.handleSelect();
                            } else if (_currentScreen == IpodScreenState.playlists) {
                              _playlistsKey.currentState?.handleSelect();
                            } else if (_currentScreen == IpodScreenState.localSongs) {
                              _localSongsKey.currentState?.handleSelect();
                            } else if (_currentScreen == IpodScreenState.musicSeparator) {
                              _separatorKey.currentState?.handleCenterClick();
                            }
                          },
                          onLongPress: () async {
                            if (_currentTrack != null && _currentScreen == IpodScreenState.home) {
                              Vibration.vibrate(duration: 50);
                              
                              final prefs = await SharedPreferences.getInstance();
                              List<String> favs = prefs.getStringList('favorites_list') ?? [];
                              bool isFav = favs.any((jsonStr) {
                                try {
                                  return json.decode(jsonStr)['id'].toString() == _currentTrack!.id.toString();
                                } catch (_) { return false; }
                              });
                              
                              if (mounted) {
                                setState(() {
                                  _isCurrentTrackFavorite = isFav;
                                  _showTrackOptions = true;
                                  _trackOptionsIndex = 0;
                                });
                              }
                            }
                          },
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isDarkMode ? const Color(0xFF050505) : const Color(0xFFB0B0B0),
                                width: 1.5,
                              ),
                              // Metallic reflection sweep
                              gradient: SweepGradient(
                                colors: _isDarkMode ? const [
                                  Color(0xFF111111),
                                  Color(0xFF333333),
                                  Color(0xFF111111),
                                  Color(0xFF000000),
                                  Color(0xFF111111),
                                  Color(0xFF333333),
                                  Color(0xFF111111),
                                ] : const [
                                  Color(0xFFC0C0C0),
                                  Color(0xFFF8F8F8),
                                  Color(0xFFC0C0C0),
                                  Color(0xFF909090),
                                  Color(0xFFC0C0C0),
                                  Color(0xFFF8F8F8),
                                  Color(0xFFC0C0C0),
                                ],
                                stops: const [0.0, 0.15, 0.35, 0.5, 0.65, 0.85, 1.0],
                                transform: const GradientRotation(pi / 4),
                              ),
                              boxShadow: [
                                // Inner shadow to look recessed from the wheel
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  offset: const Offset(0, 3),
                                  blurRadius: 4,
                                  spreadRadius: -1,
                                ),
                                BoxShadow(
                                  color: _isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.white60,
                                  offset: const Offset(0, -2),
                                  blurRadius: 2,
                                  blurStyle: BlurStyle.inner,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ), // Close Center
                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter to generate the horizontal brushed metal grain
class BrushedMetalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed so it doesn't flicker on rebuild
    final random = Random(42);
    final paint = Paint()..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 1.0) {
      // Generate random intensity for the stroke
      double intensity = random.nextDouble() * 0.05; // Very subtle noise
      bool isLight = random.nextBool();
      
      paint.color = isLight 
          ? Colors.white.withValues(alpha: intensity * 1.5) 
          : Colors.black.withValues(alpha: intensity);
          
      // Draw horizontal line across the screen
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText({super.key, required this.text, required this.style});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScrolling();
    });
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          double newPos = _scrollController.offset + 1.5;
          if (newPos > maxScroll + 30) {
            _scrollController.jumpTo(0.0);
          } else {
            _scrollController.jumpTo(newPos);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: double.infinity);
        
        if (textPainter.size.width <= constraints.maxWidth) {
          return Center(child: Text(widget.text, style: widget.style, maxLines: 1));
        } else {
          return SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.only(right: 30),
              child: Text(widget.text, style: widget.style, maxLines: 1),
            ),
          );
        }
      },
    );
  }
}

class ClickWheelButton extends StatefulWidget {
  final Widget? child;
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(LongPressEndDetails)? onLongPressEnd;
  final ValueChanged<bool>? onStateChange;
  final double pressedOpacity;

  const ClickWheelButton({
    super.key,
    this.child,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onStateChange,
    this.pressedOpacity = 0.3,
  });

  @override
  State<ClickWheelButton> createState() => _ClickWheelButtonState();
}

class _ClickWheelButtonState extends State<ClickWheelButton> {
  bool _isPressed = false;

  void _setPressed(bool pressed) {
    if (_isPressed == pressed) return;
    setState(() => _isPressed = pressed);
    if (widget.onStateChange != null) {
      widget.onStateChange!(pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onLongPressStart: (details) {
        _setPressed(true);
        if (widget.onLongPressStart != null) widget.onLongPressStart!(details);
      },
      onLongPressEnd: (details) {
        _setPressed(false);
        if (widget.onLongPressEnd != null) widget.onLongPressEnd!(details);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 50),
        opacity: _isPressed ? widget.pressedOpacity : 1.0,
        child: widget.child,
      ),
    );
  }
}

class ClickWheelPainter extends CustomPainter {
  final int? pressedSector;
  final bool isDarkMode;

  ClickWheelPainter({this.pressedSector, required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Draw 45 degree separation lines
    final linePaint = Paint()
      ..color = isDarkMode ? Colors.black38 : Colors.black12
      ..strokeWidth = 1.5;

    // 45 degrees = pi / 4
    for (int i = 0; i < 4; i++) {
      final angle = (pi / 4) + (i * pi / 2);
      final p2 = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawLine(center, p2, linePaint);
    }

    // Draw darkened sector if pressed
    if (pressedSector != null && pressedSector! >= 0 && pressedSector! <= 3) {
      final highlightPaint = Paint()
        ..color = isDarkMode ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      
      final startAngle = (pressedSector! * pi / 2) - (3 * pi / 4);
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        pi / 2, // 90 degrees sweep
        true,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ClickWheelPainter old) => 
      old.pressedSector != pressedSector || old.isDarkMode != isDarkMode;
}
