import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../fallback/domain/fallback_manager.dart';

class WebViewScreen extends StatefulWidget {
  final List<String> urls;
  final String secretToken;

  const WebViewScreen({super.key, required this.urls, required this.secretToken});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  int _currentUrlIndex = 0;
  InAppWebViewController? webViewController;
  late final InAppWebViewSettings settings;
  
  bool _isInitializing = true;
  bool _isSwitching = false;
  // الجدار العازل المطلق: عند تفعيله يتم إخفاء المتصفح من الوجود لمنع عرض نصوص 404
  bool _isEmergencyFallback = false; 
  
  bool _isTotalFailure = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    settings = InAppWebViewSettings(
      transparentBackground: true, 
      hardwareAcceleration: true,  
      javaScriptEnabled: true,
      cacheEnabled: true,
      useShouldInterceptRequest: false, 
      supportMultipleWindows: false,
    );
    _initFirstUrl();
  }

  Future<void> _initFirstUrl() async {
    await _injectSecurityToken(widget.urls[_currentUrlIndex]);
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _injectSecurityToken(String url) async {
    final cookieManager = CookieManager.instance();
    final uri = WebUri(url);
    await cookieManager.setCookie(
      url: uri,
      name: "Edge-Auth-Token",
      value: widget.secretToken,
      isSecure: true, 
      isHttpOnly: false,
    );
    debugPrint('🔐 تم حقن الدرع الأمني بنجاح للرابط: $url');
  }

  // المحرك الذكي للتعامل مع انهيارات الإطار الرئيسي (Main Frame)
  void _handleMainFrameError() async {
    if (_isSwitching || _isEmergencyFallback) return; // منع التكرار
    
    setState(() {
      _isSwitching = true; // رفع الجدار الأسود فوراً
    });
    
    await webViewController?.stopLoading();

    if (_currentUrlIndex < widget.urls.length - 1) {
      _currentUrlIndex++;
      final nextUrl = widget.urls[_currentUrlIndex];
      debugPrint('🔄 تحويل صامت إلى الاستضافة البديلة: $nextUrl');
      
      await _injectSecurityToken(nextUrl);
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(nextUrl)));
      
      if (mounted) setState(() => _isSwitching = false);
    } else {
      debugPrint('❌ جميع الروابط فشلت. جاري استدعاء حاوية الطوارئ المشفرة...');
      if (mounted) {
        setState(() {
          // تدمير المتصفح من واجهة المستخدم بالكامل لضمان عدم ظهور أي نص غريب
          _isEmergencyFallback = true; 
        });
      }
      await _executeSecondaryFallbackLifecycle('All URLs returned HTTP Errors.');
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
        // استدعاء واجهة (عليك ترقية التطبيق الآن) مع زري التنزيل والخروج الصارم (exit(0))
        await FallbackManager.executeFallback(context, fallbackEncryptedUrl);
      } else {
         throw Exception('Fallback URL is empty.');
      }
    } catch (secondaryError) {
      if (mounted) {
        setState(() {
          _isTotalFailure = true;
          _errorMessage = 'تعذر الاتصال بالخوادم الآمنة.\n\n[P]: $primaryErrorText\n\n[S]: $secondaryError';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () {
                     setState(() {
                       _isTotalFailure = false;
                       _isInitializing = true;
                       _isEmergencyFallback = false;
                       _currentUrlIndex = 0;
                     });
                     _initFirstUrl();
                  },
                )
              ],
            ),
          ),
        ),
      );
    }

    // الجدار البصري الأسود أثناء التهيئة أو عند تفعيل محرك الطوارئ
    // هذا الشرط يحجب المتصفح من الوجود، فلا يمكن رؤية أي نص أو شاشة بيضاء لـ Netlify
    if (_isInitializing || _isEmergencyFallback) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.urls[_currentUrlIndex])),
              initialSettings: settings,
              onWebViewCreated: (controller) async {
                webViewController = controller;
                if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
                  await windowManager.show();
                  await windowManager.focus();
                }
              },
              onReceivedHttpError: (controller, request, errorResponse) async {
                // الاعتماد على isForMainFrame لتجاهل أي تغييرات في الرابط واصطياد الخطأ بدقة 100%
                if (request.isForMainFrame == true) {
                  _handleMainFrameError();
                }
              },
              onReceivedError: (controller, request, error) async {
                if (request.isForMainFrame == true) {
                  _handleMainFrameError();
                }
              },
            ),
            // جدار عزل صلب يغطي المتصفح تماماً أثناء الانتقال بين الروابط
            if (_isSwitching)
               Container(color: Colors.black), 
          ],
        ),
      ),
    );
  }
}
