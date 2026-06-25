import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audius_service.dart';

class FavoritesScreen extends StatefulWidget {
  final bool isDarkMode;
  final bool isLocalMode;
  final void Function(List<Track>, int, [String?]) onTrackSelected;
  
  const FavoritesScreen({super.key, required this.isDarkMode, required this.isLocalMode, required this.onTrackSelected});

  @override
  State<FavoritesScreen> createState() => FavoritesScreenState();
}

class FavoritesScreenState extends State<FavoritesScreen> {
  List<Track> _favorites = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> favsJson = prefs.getStringList('favorites_list') ?? [];
    
    List<Track> loadedTracks = [];
    for (String jsonStr in favsJson) {
      try {
        final Map<String, dynamic> trackMap = json.decode(jsonStr);
        final track = Track.fromLocalJson(trackMap);
        if (track.isLocal == widget.isLocalMode) {
          loadedTracks.add(track);
        }
      } catch (e) {
        debugPrint('Error parsing favorite track: $e');
      }
    }

    if (mounted) {
      setState(() {
        _favorites = loadedTracks;
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
    if (_favorites.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _favorites.length;
      if (_selectedIndex < 0) {
        _selectedIndex += _favorites.length;
      }
      _scrollToSelection();
    });
  }

  void handleSelect() {
    if (_favorites.isNotEmpty) {
      widget.onTrackSelected(_favorites, _selectedIndex, 'Favorites');
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

    if (_favorites.isEmpty) {
      return Center(
        child: Text(
          'No Favorites yet',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Helvetica',
          ),
        ),
      );
    }

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
            'Favorites',
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
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final track = _favorites[index];
              final isSelected = index == _selectedIndex;
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
