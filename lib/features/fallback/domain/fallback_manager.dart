import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../../core/security/crypto_manager.dart';
import '../presentation/fallback_screen.dart';

class FallbackManager {
  static Future<void> executeFallback(BuildContext context, String fallbackUrl) async {
    try {
      // المعالجة الذكية: تحويل رابط GitHub العادي إلى رابط Raw خام برمجياً لتجنب جلب صفحة HTML
      String safeUrl = fallbackUrl;
      if (safeUrl.contains('github.com') && safeUrl.contains('/blob/')) {
        safeUrl = safeUrl.replaceFirst('github.com', 'raw.githubusercontent.com').replaceFirst('/blob/', '/');
        debugPrint('🔄 تم التصحيح التلقائي لرابط GitHub إلى المسار الخام: $safeUrl');
      }

      final response = await http.get(Uri.parse(safeUrl));
      if (response.statusCode == 200) {
        final cipherText = response.body;
        final payload = CryptoManager.decryptPayload(cipherText);
        
        if (!context.mounted) return;
        if (payload != null) {
          // استدعاء الحاوية المخصصة (عليك ترقية التطبيق الآن) وسط الشاشة السوداء
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              opaque: false,
              pageBuilder: (context, animation, secondaryAnimation) => FallbackScreen(config: payload),
            ),
            (route) => false,
          );
          return;
        } else {
          throw Exception('فشل فك التشفير: مفتاح غير متطابق أو حمولة فارغة.');
        }
      } else {
        throw Exception('فشل الاتصال بـ GitHub: رمز الاستجابة ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('خطأ حرج في مسار الطوارئ: $e'); 
    }
  }
}
