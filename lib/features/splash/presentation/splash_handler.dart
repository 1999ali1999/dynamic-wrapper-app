import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../webview/presentation/webview_screen.dart';
import '../../fallback/domain/fallback_manager.dart';

class SplashHandler extends StatefulWidget {
  const SplashHandler({super.key});

  @override
  State<SplashHandler> createState() => _SplashHandlerState();
}

class _SplashHandlerState extends State<SplashHandler> {
  bool _isOfflineError = false;
  bool _isRetrying = false;
  bool _isTotalFailure = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeAppLifecycle();
  }

  Future<void> _initializeAppLifecycle() async {
    setState(() => _isTotalFailure = false);
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: Duration.zero, // تحديث فوري دائم
      ));

      await remoteConfig.fetchAndActivate();
      
      // 1. الاتصال بالمفتاح المعماري الصحيح للبيانات
      final routingConfigRaw = remoteConfig.getString('app_routing_config');
      final secretToken = remoteConfig.getString('app_secret_token');

      List<String> parsedUrls = [];

      // 2. خوارزمية التفكيك المتقدمة لكائن JSON (Map) 
      if (routingConfigRaw.isNotEmpty) {
        try {
          final decoded = json.decode(routingConfigRaw);
          if (decoded is Map<String, dynamic>) {
            // استخراج مصفوفة الروابط البديلة (Failover) بدقة
            if (decoded.containsKey('failover_urls') && decoded['failover_urls'] is List) {
              parsedUrls = List<String>.from(decoded['failover_urls']);
            } else if (decoded.containsKey('primary_url')) {
              // كإجراء احتياطي، استخدام الرابط الأساسي إذا لم تتوفر المصفوفة
              parsedUrls = [decoded['primary_url'].toString()];
            }
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في تفكيك JSON المعماري: $e');
        }
      }

      if (parsedUrls.isNotEmpty && secretToken.isNotEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            opaque: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) => WebViewScreen(
              urls: parsedUrls,
              secretToken: secretToken,
            ),
          ),
        );
        return;
      }
      throw Exception('app_routing_config field is empty or format is unrecognized.');
    } catch (primaryError) {
      debugPrint('⚠️ فشل التوجيه الأساسي: $primaryError');
      if (!mounted) return;
      await _executeSecondaryFallbackLifecycle(primaryError.toString());
    }
  }

  Future<void> _executeSecondaryFallbackLifecycle(String primaryErrorText) async {
    try {
      const secondaryOptions = FirebaseOptions(
        apiKey: 'AIzaSyAc6xP-0PgwMFwmqh2qZ7azmYSnlvmsw7M',
        appId: '1:807100912589:android:af731f00a12360b43baa84',
        messagingSenderId: '807100912589',
        projectId: 'fallback-engine',
        storageBucket: 'fallback-engine.appspot.com',
      );

      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('SecondaryFallbackApp');
      } catch (_) {
        secondaryApp = await Firebase.initializeApp(
          name: 'SecondaryFallbackApp',
          options: secondaryOptions,
        );
      }

      // تفعيل App Check للمحرك الاحتياطي
      await FirebaseAppCheck.instanceFor(app: secondaryApp).activate();

      final secondaryConfig = FirebaseRemoteConfig.instanceFor(app: secondaryApp);
      await secondaryConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: Duration.zero,
      ));

      await secondaryConfig.fetchAndActivate();
      final fallbackEncryptedUrl = secondaryConfig.getString('fallback_config_url');

      if (fallbackEncryptedUrl.isNotEmpty) {
        if (!mounted) return;
        await FallbackManager.executeFallback(context, fallbackEncryptedUrl);
      } else {
         throw Exception('Fallback URL is empty.');
      }
    } catch (secondaryError) {
      debugPrint('❌ فشل مطلق: $secondaryError');
      if (mounted) {
                    // تقييم الخطأ المبني برمجياً أياً كانت المتغيرات التي استخدمتها
            final builtError = 'تعذر الاتصال بالخوادم الآمنة.\n\n[P]: $primaryErrorText\n\n[S]: $secondaryError';
            
            // 🛡️ مستشعر الإقلاع: التفرقة بين السقوط الفعلي لخوادم Firebase وبين انقطاع الإنترنت المحلي
            if (builtError.contains('remote config fetch error') || builtError.contains('ClientException') || builtError.contains('network_error')) {
               setState(() => _isOfflineError = true);
               return;
            }
            
            // إذا كان سقوطاً حقيقياً، نمرر الانهيار التام
            setState(() {
              _isTotalFailure = true;
              _errorMessage = builtError;
            });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
        // 🛡️ واجهة العزل البصرية الخاصة بشاشة الإقلاع
    if (_isOfflineError) {
      return Scaffold(
        backgroundColor: Colors.black, // استمرار العزل البصري (Anti-Flash)
        body: StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snapshot) {
            final results = snapshot.data ?? [ConnectivityResult.none];
            final isOffline = results.isEmpty || results.contains(ConnectivityResult.none);
            
            // الاستئناف التلقائي الفوري فور عودة الإنترنت
            if (!isOffline && !_isRetrying) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _isRetrying = true);
                  // استنساخ الشاشة لإعادة دورة الإقلاع وجلب بيانات Firebase مجدداً
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => widget));
                }
              });
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 80, color: Colors.grey.shade600),
                    const SizedBox(height: 24),
                    const Text(
                      'انقطع الاتصال بالإنترنت أو تعذر الاتصال بالخوادم',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'يرجى التحقق من اتصالك. سيتم استئناف الإقلاع تلقائياً فور عودة الإنترنت.',
                      style: TextStyle(fontSize: 14, color: Colors.white54),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 48,
                      width: 200,
                      child: ElevatedButton(
                         style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.blueAccent,
                           foregroundColor: Colors.white,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                         ),
                         onPressed: _isRetrying ? null : () {
                           setState(() => _isRetrying = true);
                           Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => widget));
                         },
                         child: _isRetrying 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('إعادة المحاولة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    if (_isTotalFailure) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security_update_warning_rounded, size: 60, color: Colors.redAccent),
                const SizedBox(height: 20),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5, fontFamily: 'monospace'),
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 16)),
                  onPressed: _initializeAppLifecycle,
                )
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}
