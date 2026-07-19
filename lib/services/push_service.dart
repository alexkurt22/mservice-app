import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class PushService {
  static Future<String> sendPushToAdmins(String title, String body) async {
    try {
      final jsonString = await rootBundle.loadString('assets/firebase_credentials.json');
      final map = jsonDecode(jsonString);

      // ❗ АВТО-ЛЕКАРЬ: ЧИНИМ СЛОМАННЫЙ КЛЮЧ ПЕРЕД ОТПРАВКОЙ ❗
      String pk = map['private_key'] as String;
      pk = pk.replaceAll(RegExp(r'\\n'), '\n'); 
      pk = pk.replaceAll('-----BEGIN PRIVATE KEY-----', '');
      pk = pk.replaceAll('-----END PRIVATE KEY-----', '');
      pk = pk.replaceAll(RegExp(r'\s+'), ''); 

      String chunkedPk = '';
      for (int i = 0; i < pk.length; i += 64) {
        chunkedPk += pk.substring(i, i + 64 > pk.length ? pk.length : i + 64) + '\n';
      }
      map['private_key'] = '-----BEGIN PRIVATE KEY-----\n$chunkedPk-----END PRIVATE KEY-----\n';

      final fixedJsonString = jsonEncode(map);
      final accountCredentials = ServiceAccountCredentials.fromJson(fixedJsonString);

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final projectId = map['project_id'];

      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
      final payload = {
        'message': {
          'topic': 'admins', // Рассылка всем админам
          'notification': {
            'title': title,
            'body': body,
          },
          'android': {
            'priority': 'high', // Пробивает спящий режим
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
