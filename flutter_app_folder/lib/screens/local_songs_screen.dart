import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../services/local_audio_service.dart';
import '../services/audius_service.dart';

class LocalSongsScreen extends StatefulWidget {
  final bool isDarkMode;
  final void Function(List<Track>, int, [String?]) onTrackSelected;
  const LocalSongsScreen({super.key, required this.isDarkMode, required this.onTrackSelected});

  @override
  State<LocalSongsScreen> createState() => LocalSongsScreenState();
}

class LocalSongsScreenState extends State<LocalSongsScreen> {
  final LocalAudioService _audioService = LocalAudioService();
  List<SongModel> _songs = [];
  bool _isLoading = true;
  
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchSongs();
  }

  Future<void> _fetchSongs() async {
    List<SongModel> songs = await _audioService.getSongs();
    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    }
  }

  void _scrollToSelection() {
    if (_scrollController.hasClients && _songs.isNotEmpty) {
      double itemHeight = 60.0; 
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
    if (_songs.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _songs.length;
      if (_selectedIndex < 0) {
        _selectedIndex += _songs.length;
      }
      _scrollToSelection();
    });
  }

  void handleSelect() {
    if (_songs.isNotEmpty) {
      final tracks = _songs.map((song) => Track(
        id: song.id.toString(),
        title: song.title,
        artist: song.artist ?? 'Unknown Artist',
        isLocal: true,
        localPath: song.data,
      )).toList();
      widget.onTrackSelected(tracks, _selectedIndex, null);
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

    if (_songs.isEmpty) {
      return Center(
        child: Text(
          'No Local Songs',
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
            'Your Songs',
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
            itemCount: _songs.length,
            itemBuilder: (context, index) {
              final song = _songs[index];
              final isSelected = index == _selectedIndex;

              return Container(
                height: 60.0,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.white12 : Colors.black12)),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    tileColor: isSelected ? (widget.isDarkMode ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)) : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    leading: QueryArtworkWidget(
                      key: ValueKey(song.id),
                      keepOldArtwork: true,
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Icon(
                      Icons.music_note, 
                      color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white70 : Colors.black87), 
                      size: 30
                    ),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : (widget.isDarkMode ? Colors.white : Colors.black), 
                      fontFamily: 'Helvetica', 
                      fontSize: 14, 
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  subtitle: Text(
                    song.artist ?? "Unknown Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white70 : (widget.isDarkMode ? Colors.white54 : Colors.black54), 
                      fontFamily: 'Helvetica', 
                      fontSize: 12
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
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
