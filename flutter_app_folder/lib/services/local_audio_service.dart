import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class LocalAudioService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ use audio, else use storage
      PermissionStatus status;
      if (await Permission.audio.isRestricted) {
         status = await Permission.storage.request();
      } else {
         status = await Permission.audio.request();
      }

      if (status.isGranted) {
        return true;
      }
      
      // Fallback request
      var fallbackStatus = await Permission.storage.request();
      return fallbackStatus.isGranted;
    }
    return false; // For iOS or other platforms, we might need different logic
  }

  static List<SongModel>? _cachedSongs;

  Future<List<SongModel>> getSongs({bool forceRefresh = false}) async {
    if (_cachedSongs != null && !forceRefresh) {
      return _cachedSongs!;
    }

    bool hasPermission = await requestPermission();
    if (!hasPermission) {
      return [];
    }

    List<SongModel> songs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    // Filter out unwanted app audio (WhatsApp, Cliq, etc) by only allowing
    // files located within Music or Download(s) directories.
    _cachedSongs = songs.where((song) {
      final path = song.data.toLowerCase();
      return path.contains('/music/') || 
             path.contains('/download/') || 
             path.contains('/downloads/');
    }).toList();
    
    return _cachedSongs!;
  }
}
