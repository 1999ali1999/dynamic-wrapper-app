// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() {
  final key = encrypt.Key.fromUtf8('MySuperSecretKeyForFallback2026!');
  // 🛡️ التعديل الجذري: تطابق متطابق مع التطبيق
  final iv = encrypt.IV.fromUtf8('FallbackInitVect');
  final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

  final jsonPayload = {
    "message": "عليك ترقية التطبيق الآن",
    "android_url": "https://play.google.com/store/apps/details?id=com.example.app",
    "windows_url": "https://example.com/download/windows",
    "macos_url": "https://example.com/download/macos",
    "linux_url": "https://example.com/download/linux"
  };

  final plainText = json.encode(jsonPayload);
  final encrypted = encrypter.encrypt(plainText, iv: iv);

  print('\n=== انسخ هذا النص المشفر وضعه في ملف على GitHub ===');
  print(encrypted.base64);
  print('===================================================\n');
}
