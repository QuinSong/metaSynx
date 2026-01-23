import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';

class RoomService {
  /// Creates a new relay room and returns room_id and room_secret
  static Future<RoomCredentials> createRoom() async {
    final response = await http.post(
      Uri.parse('https://$relayServer/ws/relay/create-room'),
      headers: {
        'x-api-key': apiKey,
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create room: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return RoomCredentials(
      roomId: data['room_id'],
      roomSecret: data['room_secret'],
    );
  }

  /// Generates QR code payload
  static String generateQrPayload(String roomId, String roomSecret) {
    final qrPayload = {
      'server': relayServer,
      'room': roomId,
      'secret': roomSecret,
      'v': 2,
    };
    return jsonEncode(qrPayload);
  }
}

class RoomCredentials {
  final String roomId;
  final String roomSecret;

  RoomCredentials({
    required this.roomId,
    required this.roomSecret,
  });
}
