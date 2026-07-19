import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../secret/firebase_secret.dart'; // ❗ ПОДКЛЮЧАЕМ НАШ СГЕНЕРИРОВАННЫЙ КЛЮЧ

class PushService {
  static Future<String> sendPushToAdmins(String title, String body) async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(firebaseSecret);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final projectId = jsonDecode(firebaseSecret)['project_id'];

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
