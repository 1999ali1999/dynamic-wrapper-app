import 'dart:io';

void main() async {
  print('🛠️ بدء الحقن المعماري لمحرك المرونة الشبكية والتعافي التلقائي...');

  // 1. تثبيت حزمة مراقبة الشبكة الأحدث والأكثر استقراراً
  print('📦 جاري دمج حزمة connectivity_plus...');
  final result = await Process.run('flutter', ['pub', 'add', 'connectivity_plus']);
  if (result.exitCode == 0) {
    print('✅ تم إضافة connectivity_plus بنجاح.');
  } else {
    print('⚠️ ملاحظة: ${result.stderr}');
  }

  // 2. الترقية الشاملة لملف WebViewScreen
  final webviewFile = File('lib/features/webview/presentation/webview_screen.dart');
  
  if (await webviewFile.exists()) {
    final webviewContent = r'''
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _isEmergencyFallback = false; 
  
  bool _isTotalFailure = false;
  String _errorMessage = '';

  // 🛡️ متغيرات محرك المرونة الشبكية
  bool _isOfflineError = false;
  bool _isRetrying = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

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
    _initNetworkEngine();
    _initFirstUrl();
  }

  // 🛡️ استشعار الشبكة والتعافي التلقائي الفوري
  void _initNetworkEngine() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // إذا كان هناك اتصال، وكنا عالقين في شاشة الخطأ الشبكي، نفذ إعادة المحاولة تلقائياً
      if (!results.contains(ConnectivityResult.none) && _isOfflineError) {
         debugPrint('🌐 عودة الإنترنت! جاري الاستئناف التلقائي...');
         _performRetry();
      }
    });
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
  }

  // 🛡️ دالة إعادة المحاولة (اليدوية والتلقائية)
  Future<void> _performRetry() async {
    if (_isRetrying) return; // منع التكرار

    setState(() {
      _isRetrying = true;
    });

    // التحقق من حالة الشبكة قبل محاولة التحميل
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      // لا يزال منقطعاً
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
      return;
    }

    setState(() {
      _isOfflineError = false;
      _isSwitching = true; // رفع الجدار الأسود لمنع الوميض أثناء إعادة التحميل
    });

    await _injectSecurityToken(widget.urls[_currentUrlIndex]);
    await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.urls[_currentUrlIndex])));

    if (mounted) {
      setState(() {
        _isRetrying = false;
        _isSwitching = false;
      });
    }
  }

  // المحرك الذكي للتعامل مع انهيارات الإطار الرئيسي (الخاصة بالخوادم و 404)
  void _handleMainFrameError() async {
    if (_isSwitching || _isEmergencyFallback || _isOfflineError) return; 
    
    setState(() {
      _isSwitching = true; 
    });
    
    await webViewController?.stopLoading();

    if (_currentUrlIndex < widget.urls.length - 1) {
      _currentUrlIndex++;
      final nextUrl = widget.urls[_currentUrlIndex];
      
      await _injectSecurityToken(nextUrl);
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(nextUrl)));
      
      if (mounted) setState(() => _isSwitching = false);
    } else {
      if (mounted) {
        setState(() {
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
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isTotalFailure) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
             // ... واجهة الفشل المطلق السابقة ...
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security_update_warning_rounded, size: 60, color: Colors.redAccent),
                const SizedBox(height: 20),
                Text(_errorMessage, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5, fontFamily: 'monospace'), textAlign: TextAlign.left, textDirection: TextDirection.ltr),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 16)),
                  onPressed: () {
                     setState(() { _isTotalFailure = false; _isInitializing = true; _isEmergencyFallback = false; _currentUrlIndex = 0; });
                     _initFirstUrl();
                  },
                )
              ],
            ),
          ),
        ),
      );
    }

    // 🛡️ واجهة الانقطاع الشبكي المتجاوبة (Responsive)
    if (_isOfflineError) {
      return Scaffold(
        backgroundColor: Colors.black, // الحفاظ على الهوية البصرية والعزل البصري
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // يمكن استبدال هذه الأيقونة بصورة الشعار (SVG) الخاص بك مستقبلاً
                Icon(Icons.wifi_off_rounded, size: 80, color: Colors.grey.shade600),
                const SizedBox(height: 24),
                const Text(
                  'انقطع الاتصال بالإنترنت أو تعذر جلب المورد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 12),
                const Text(
                  'يرجى التحقق من اتصالك. سيتم استئناف التطبيق تلقائياً فور عودة الإنترنت.',
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
                    onPressed: _isRetrying ? null : _performRetry,
                    child: _isRetrying
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('إعادة المحاولة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isInitializing || _isEmergencyFallback) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
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
              // 🛡️ اصطياد أخطاء الاتصال والانقطاع (Network & Resource Failures)
              onLoadError: (controller, request, code, message) async {
                if (request.isForMainFrame == true) {
                  debugPrint('⚠️ خطأ في تحميل المورد أو الشبكة: $code - $message');
                  // رمز الخطأ يختلف باختلاف المنصة، لكننا نعتبر أي فشل تحميل هنا مشكلة شبكة/مورد
                  if (mounted) {
                    setState(() {
                       _isOfflineError = true;
                    });
                  }
                }
              },
              // اصطياد أخطاء الخادم (مثل 404 DEPLOYMENT_NOT_FOUND)
              onReceivedHttpError: (controller, request, errorResponse) async {
                if (request.isForMainFrame == true) {
                  _handleMainFrameError();
                }
              },
            ),
            if (_isSwitching) Container(color: Colors.black), 
          ],
        ),
      ),
    );
  }
}
''';
    await webviewFile.writeAsString(webviewContent);
    print('✅ تم حقن محرك المرونة الشبكية المتكامل بنجاح وبدون أي اختزال للأكواد السابقة.');
  } else {
    print('❌ لم يتم العثور على ملف WebViewScreen.');
  }
}