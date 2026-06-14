import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../../webview/presentation/webview_screen.dart';

class SplashHandler extends StatefulWidget {
  const SplashHandler({super.key});

  @override
  State<SplashHandler> createState() => _SplashHandlerState();
}

class _SplashHandlerState extends State<SplashHandler> {
  @override
  void initState() {
    super.initState();
    _fetchConfigAndNavigate();
  }

  Future<void> _fetchConfigAndNavigate() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(seconds: 0),
      ));
      
      await remoteConfig.fetchAndActivate();

      // جلب الروابط (نظام مرن يقبل JSON أو نصوص عادية مفصولة بفواصل)
      String configStr = remoteConfig.getString('app_routing_config');
      String secretToken = remoteConfig.getString('app_secret_token');
      
      List<String> urls = [];
      try {
        final decoded = jsonDecode(configStr);
        if (decoded is Map && decoded.containsKey('primary_url')) {
          urls.add(decoded['primary_url']);
          if (decoded['failover_urls'] != null) {
            urls.addAll(List<String>.from(decoded['failover_urls']));
          }
        } else if (decoded is List) {
          urls = List<String>.from(decoded);
        }
      } catch (_) {
        // في حال كان الإدخال في Firebase نصاً عادياً مفصولاً بفاصلة
        urls = configStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }

      // الانتقال إلى WebView بعد جلب الروابط
      if (urls.isNotEmpty && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => WebViewScreen(
              urls: urls,
              secretToken: secretToken,
            ),
            transitionDuration: Duration.zero, // انتقال فوري بدون تأخير بصري
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في جلب بيانات Firebase: $e');
      // يتم البقاء على الشاشة الشفافة أو عرض تنبيه عدم اتصال
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(), // يحافظ على الشفافية أثناء الاتصال بـ Firebase
    );
  }
}
