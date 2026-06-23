import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Track {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    String? art;
    if (json['artwork'] != null) {
      art = json['artwork']['480x480'] ?? json['artwork']['150x150'] ?? json['artwork']['1000x1000'];
    }
    
    return Track(
      id: json['id'] is String ? json['id'] : json['id'].toString(),
      title: json['title'] ?? 'Unknown Title',
      artist: json['user'] != null ? json['user']['name'] : 'Unknown Artist',
      artworkUrl: art,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artworkUrl': artworkUrl,
    };
  }
  
  factory Track.fromLocalJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'].toString(),
      title: json['title'],
      artist: json['artist'],
      artworkUrl: json['artworkUrl'],
    );
  }
}

class AudiusService {
  final String appName = 'MusicSeparatorApp';
  final String _hostNode = 'https://discoveryprovider.audius.co';

  Future<String> getHostNode() async {
    return _hostNode;
  }

  Future<List<Track>> getTrendingTracks() async {
    final host = await getHostNode();
    try {
      final response = await http.get(Uri.parse('$host/v1/tracks/trending?app_name=$appName'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> tracks = data['data'] ?? [];
        return tracks.map((t) => Track.fromJson(t)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching trending track: $e');
    }
    return [];
  }

  Future<String> getStreamUrl(String trackId) async {
    final host = await getHostNode();
    return '$host/v1/tracks/$trackId/stream?app_name=$appName';
  }

  Future<List<Track>> searchTracks(String query) async {
    final host = await getHostNode();
    try {
      final response = await http.get(Uri.parse('$host/v1/tracks/search?query=$query&app_name=$appName'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> tracks = data['data'] ?? [];
        return tracks.map((t) => Track.fromJson(t)).toList();
      }
    } catch (e) {
      debugPrint('Error searching tracks: $e');
    }
    return [];
  }
}
