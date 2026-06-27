import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';

class CryptoManager {
  static final _key = encrypt.Key.fromUtf8('MySuperSecretKeyForFallback2026!'); 
  // 🛡️ التعديل الجذري: استخدام متجه تهيئة ثابت 16 حرفاً بدلاً من المولد العشوائي
  static final _iv = encrypt.IV.fromUtf8('FallbackInitVect');

  static Map<String, dynamic>? decryptPayload(String cipherText) {
    try {
      if (cipherText.trim().isEmpty) {
         throw Exception('الملف المستلم من GitHub فارغ تماماً.');
      }

      String actualPayload = '';
      final words = cipherText.split(RegExp(r'\s+'));
      for (var word in words) {
        if (word.length > actualPayload.length) {
          actualPayload = word;
        }
      }

      String unpadded = actualPayload.replaceAll(RegExp(r'[^a-zA-Z0-9+/]'), '');

      String cleanCipherText = unpadded;
      if (unpadded.length % 4 == 2) {
        cleanCipherText += '==';
      } else if (unpadded.length % 4 == 3) {
        cleanCipherText += '=';
      } else if (unpadded.length % 4 == 1) {
        throw Exception('حمولة Base64 المستخرجة معطوبة رياضياً ولا يمكن إصلاحها.');
      }

      if (cleanCipherText.length < 50) {
         throw Exception('الحمولة المستخرجة قصيرة جداً (طولها ${cleanCipherText.length}).');
      }

      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt64(cleanCipherText, iv: _iv);
      return json.decode(decrypted);
      
    } catch (e) {
      throw Exception('فشل التشفير الداخلي: $e'); 
    }
  }
}
