import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audius_service.dart';

class SearchScreen extends StatefulWidget {
  final bool isDarkMode;
  final void Function(Track, [String?]) onTrackSelected;

  const SearchScreen({
    super.key,
    required this.isDarkMode,
    required this.onTrackSelected,
  });

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final AudiusService _audiusService = AudiusService();
  
  List<Track> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  final String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _<*";
  int _selectedIndex = 0;
  
  bool _isKeyboardActive = true;
  int _selectedResultIndex = 0;

  void _scrollToSelection() {
    if (_scrollController.hasClients) {
      double itemHeight = 56.0; 
      double viewportHeight = _scrollController.position.viewportDimension;
      double currentScroll = _scrollController.offset;
      double itemTop = _selectedResultIndex * itemHeight;
      double itemBottom = itemTop + itemHeight;
      
      if (itemTop < currentScroll) {
        _scrollController.animateTo(itemTop, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      } else if (itemBottom > currentScroll + viewportHeight) {
        _scrollController.animateTo(itemBottom - viewportHeight, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    }
  }

  void moveSelection(int delta) {
    setState(() {
      if (_isKeyboardActive) {
        _selectedIndex = (_selectedIndex + delta) % _alphabet.length;
        if (_selectedIndex < 0) {
          _selectedIndex += _alphabet.length;
        }
      } else {
        if (_searchResults.isNotEmpty) {
          if (delta < 0 && _selectedResultIndex == 0) {
            // Scroll up past the first result to return to the keyboard
            _isKeyboardActive = true;
          } else {
            _selectedResultIndex = (_selectedResultIndex + delta) % _searchResults.length;
            if (_selectedResultIndex < 0) {
              _selectedResultIndex += _searchResults.length;
            }
            _scrollToSelection();
          }
        }
      }
    });
  }

  void handleSelect() {
    if (!_isKeyboardActive) {
      if (_searchResults.isNotEmpty) {
        widget.onTrackSelected(_searchResults[_selectedResultIndex]);
      }
      return;
    }

    setState(() {
      final selectedChar = _alphabet[_selectedIndex];
      if (selectedChar == '<') {
        if (_searchQuery.isNotEmpty) {
          _searchQuery = _searchQuery.substring(0, _searchQuery.length - 1);
        }
      } else if (selectedChar == '_') {
        _searchQuery += ' ';
      } else if (selectedChar == '*') {
        if (_searchResults.isNotEmpty) {
          _isKeyboardActive = false;
          _selectedResultIndex = 0;
        }
        return; // Don't trigger search again when hitting DONE
      } else {
        _searchQuery += selectedChar;
      }
    });
    _onSearchChanged(_searchQuery);
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch();
    });
  }

  void _performSearch() async {
    final query = _searchQuery.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    final results = await _audiusService.searchTracks(query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.isDarkMode 
                  ? const [Color(0xFF333333), Color(0xFF111111)] 
                  : const [Color(0xFFF8F8F8), Color(0xFFC0C0C0)],
            ),
            border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.black26)),
          ),
          child: Text(
            'Search',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.isDarkMode ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontFamily: 'Helvetica',
              fontSize: 14,
            ),
          ),
        ),

        // Results
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        'No results found',
                        style: TextStyle(
                          color: widget.isDarkMode ? Colors.white54 : Colors.black54,
                          fontFamily: 'Helvetica',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final track = _searchResults[index];
                        final bool isSelected = !_isKeyboardActive && index == _selectedResultIndex;
                        
                        return SizedBox(
                          height: 56.0,
                          child: ListTile(
                          tileColor: isSelected 
                              ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) 
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            visualDensity: VisualDensity.compact,
                            leading: Container(
                              width: 32,
                              height: 32,
                              color: Colors.grey,
                              child: track.artworkUrl != null
                                  ? Image.network(track.artworkUrl!, fit: BoxFit.cover)
                                  : const Icon(Icons.music_note, size: 16),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected 
                                    ? Colors.white 
                                    : (widget.isDarkMode ? Colors.white : Colors.black),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Helvetica',
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected 
                                    ? Colors.white70 
                                    : (widget.isDarkMode ? Colors.white54 : Colors.black54),
                                fontSize: 11,
                                fontFamily: 'Helvetica',
                              ),
                            ),
                            onTap: () {
                              widget.onTrackSelected(track);
                            },
                          ),
                        );
                      },
                    ),
        ),

        // Typed Query Display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFEBEBEB),
            border: Border(top: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.black26)),
          ),
          child: Text(
            _searchQuery.isEmpty ? "Search..." : _searchQuery,
            style: TextStyle(
              color: widget.isDarkMode ? Colors.white : Colors.black,
              fontFamily: 'Helvetica',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),

        // Alphabet Strip
        if (_isKeyboardActive)
          Container(
          height: 40,
          decoration: BoxDecoration(
            color: widget.isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFD4D4D4),
            border: Border(top: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.black26)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              int index = (_selectedIndex + (i - 3)) % _alphabet.length;
              if (index < 0) index += _alphabet.length;
              bool isSelected = _isKeyboardActive && i == 3;
              String char = _alphabet[index];
              String display = char == '_' ? 'SP' : char == '<' ? 'DEL' : char == '*' ? 'OK' : char;
              
              return Container(
                width: 36,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected 
                      ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  display,
                  style: TextStyle(
                    color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white70 : Colors.black87),
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
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
}
