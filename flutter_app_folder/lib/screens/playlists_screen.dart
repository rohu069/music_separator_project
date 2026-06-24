import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audius_service.dart';

class PlaylistsScreen extends StatefulWidget {
  final bool isDarkMode;
  final bool isLocalMode;
  final void Function(List<Track>, int, [String?]) onTrackSelected;
  
  const PlaylistsScreen({super.key, required this.isDarkMode, required this.isLocalMode, required this.onTrackSelected});

  @override
  State<PlaylistsScreen> createState() => PlaylistsScreenState();
}

class PlaylistsScreenState extends State<PlaylistsScreen> {
  Map<String, List<Track>> _playlists = {};
  String? _selectedPlaylistName;
  bool _isLoading = true;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    String? playlistsDataStr = prefs.getString('playlists_data');
    
    Map<String, List<Track>> loadedData = {};
    if (playlistsDataStr != null) {
      try {
        final Map<String, dynamic> data = json.decode(playlistsDataStr);
        data.forEach((key, value) {
          List<Track> tracks = [];
          if (value is List) {
            for (var item in value) {
              if (item is String) {
                final track = Track.fromLocalJson(json.decode(item));
                if (track.isLocal == widget.isLocalMode) {
                  tracks.add(track);
                }
              }
            }
          }
          if (tracks.isNotEmpty) {
            loadedData[key] = tracks;
          }
        });
      } catch (e) {
        debugPrint('Error parsing playlists data: $e');
      }
    }

    if (mounted) {
      setState(() {
        _playlists = loadedData;
        _isLoading = false;
      });
    }
  }

  void _scrollToSelection() {
    if (_scrollController.hasClients) {
      double itemHeight = 44.0; 
      double viewportHeight = _scrollController.position.viewportDimension;
      double currentScroll = _scrollController.offset;
      double itemTop = _selectedIndex * itemHeight;
      double itemBottom = itemTop + itemHeight;
      
      if (itemTop < currentScroll) {
        _scrollController.animateTo(itemTop, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      } else if (itemBottom > currentScroll + viewportHeight) {
        _scrollController.animateTo(itemBottom - viewportHeight, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    }
  }

  void moveSelection(int delta) {
    if (_playlists.isEmpty) return;
    int maxItems = _selectedPlaylistName == null 
        ? _playlists.length 
        : _playlists[_selectedPlaylistName!]!.length + 1;
        
    if (maxItems == 0) return;
    
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % maxItems;
      if (_selectedIndex < 0) {
        _selectedIndex += maxItems;
      }
      _scrollToSelection();
    });
  }

  void handleSelect() {
    if (_selectedPlaylistName == null) {
      if (_playlists.isNotEmpty) {
        setState(() {
          _selectedPlaylistName = _playlists.keys.toList()[_selectedIndex];
          _selectedIndex = 0;
        });
      }
    } else {
      if (_selectedIndex == 0) {
        setState(() {
          _selectedPlaylistName = null;
          _selectedIndex = 0;
        });
      } else {
        widget.onTrackSelected(_playlists[_selectedPlaylistName!]!, _selectedIndex - 1, _selectedPlaylistName);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.grey));
    }

    if (_playlists.isEmpty) {
      return Center(
        child: Text(
          'No Playlists yet',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Helvetica',
          ),
        ),
      );
    }

    List<String> keys = _playlists.keys.toList();
    bool isRoot = _selectedPlaylistName == null;
    int itemCount = isRoot ? keys.length : _playlists[_selectedPlaylistName!]!.length + 1;

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
            isRoot ? 'Playlists' : _selectedPlaylistName!,
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
          child: ListView.builder(
            controller: _scrollController,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final isSelected = index == _selectedIndex;
              
              if (!isRoot && index == 0) {
                return Container(
                  height: 44.0,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.white12 : Colors.black12)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      tileColor: isSelected ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    title: Text(
                      'Back',
                      style: TextStyle(color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black), fontFamily: 'Helvetica', fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      handleSelect();
                    },
                  ),
                  ),
                );
              }

              if (isRoot) {
                String playlistName = keys[index];
                return Container(
                  height: 44.0,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.white12 : Colors.black12)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      tileColor: isSelected ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    title: Text(
                      playlistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black), fontFamily: 'Helvetica', fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    trailing: Icon(Icons.chevron_right, size: 16, color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white30 : Colors.black38)),
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      handleSelect();
                    },
                  ),
                  ),
                );
              }

              final track = _playlists[_selectedPlaylistName!]![index - 1];
              return Container(
                height: 44.0,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.white12 : Colors.black12)),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    tileColor: isSelected ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black), fontFamily: 'Helvetica', fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    setState(() => _selectedIndex = index);
                    handleSelect();
                  },
                ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
