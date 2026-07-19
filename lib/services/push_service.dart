import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class PushService {
  static Future<String> sendPushToAdmins(String title, String body) async {
    try {
      final jsonString = await rootBundle.loadString('assets/firebase_credentials.json');
      final map = jsonDecode(jsonString);

      String pk = map['private_key'] as String;
      pk = pk.replaceAll(r'\n', '\n'); 
      pk = pk.replaceAll('-----BEGIN PRIVATE KEY-----', '');
      pk = pk.replaceAll('-----END PRIVATE KEY-----', '');
      pk = pk.replaceAll(RegExp(r'\s+'), ''); 

      String chunkedPk = '';
      for (int i = 0; i < pk.length; i += 64) {
        chunkedPk += pk.substring(i, i + 64 > pk.length ? pk.length : i + 64) + '\n';
      }
      final cleanKey = '-----BEGIN PRIVATE KEY-----\n$chunkedPk-----END PRIVATE KEY-----\n';

      final credentials = ServiceAccountCredentials.fromJson({
        "client_email": map['client_email'],
        "client_id": map['client_id'],
        "private_key": cleanKey,
        "type": "service_account",
        "project_id": map['project_id']
      });

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(credentials, scopes);
      final projectId = map['project_id'];

      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
      final payload = {
        'message': {
          'topic': 'admins',
          'notification': {
            'title': title,
            'body': body,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'sound': 'default',
              'default_vibrate_timings': true,
              'default_sound': true
            }
          }
        }
      };

      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      client.close();
      if (response.statusCode == 200) {
        return 'Успех (200)';
      } else {
        return 'Ошибка Google: ${response.statusCode} ${response.body}';
      }
    } catch (e) {
      return 'Сбой кода: $e';
    }
  }
}
