import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';
import 'features/splash/presentation/splash_handler.dart';

void main() async {
  // التأكد من تهيئة روابط Flutter الأساسية قبل أي استدعاء
  WidgetsFlutterBinding.ensureInitialized();

  // ==========================================
  // هندسة النافذة المخفية لسطح المكتب (الإقلاع الشفاف)
  // ==========================================
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720), // الأبعاد الافتراضية للنافذة
      center: true,
      backgroundColor: Colors.transparent, // شفافية تامة لقتل الشاشة البيضاء من جذورها
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // إخفاء شريط العنوان لنظام مدمج واحترافي
    );
    
    // إجبار النافذة على البقاء مخفية (Hidden) في نظام التشغيل حتى ننتهي من معالجة الأمان
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.hide();
    });
  }

  // تهيئة Firebase باستخدام الإعدادات المولدة
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // تفعيل الجدار الناري App Check
  await FirebaseAppCheck.instance.activate();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Protected Web Wrapper',
      // نبدأ بشاشة الـ Splash الشفافة لمعالجة الاتصال والمسارات
      home: SplashHandler(), 
    );
  }
}
