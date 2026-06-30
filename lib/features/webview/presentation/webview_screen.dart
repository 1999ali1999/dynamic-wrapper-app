import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _isOfflineError = false;
  bool _isRetrying = false;
  
  // 🛡️ المتغير المعماري الجديد: لمراقبة هل انهارت الصفحة فعلياً أم مجرد انقطاع خلفي
  bool _mainFrameFailed = false;
  
   
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

  void _initNetworkEngine() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isOffline = results.isEmpty || results.contains(ConnectivityResult.none);
      if (isOffline) {
        if (mounted && !_isOfflineError && !_isTotalFailure) {
          setState(() => _isOfflineError = true);
        }
      } else {
        if (mounted && _isOfflineError) {
          _performRetry();
        }
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

  // 🛡️ محرك الاستئناف الذكي المطور (Smart Resume Engine)
  Future<void> _performRetry() async {
    if (_isRetrying) return; 

    setState(() => _isRetrying = true);

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.isEmpty || connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) setState(() => _isRetrying = false);
      return;
    }

    if (_isEmergencyFallback) {
      await _executeSecondaryFallbackLifecycle('Retry from Offline UI');
    } else {
      // إذا انهارت الصفحة فعلياً بسبب التنقل أثناء الانقطاع، نعيد تحميلها.
      // أما إذا لم تنهار (مجرد انقطاع في الخلفية)، نكتفي بإزالة الغطاء الأسود ليستأنف المستخدم من مكانه!
      if (_mainFrameFailed && widget.urls.isNotEmpty) {
        setState(() => _isSwitching = true);
        await _injectSecurityToken(widget.urls[_currentUrlIndex]);
        await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.urls[_currentUrlIndex])));
        _mainFrameFailed = false;
      }
    }

    if (mounted) {
      setState(() {
        _isOfflineError = false;
        _isRetrying = false;
        _isSwitching = false;
      });
    }
  }

  void _handleMainFrameError() async {
    if (_isSwitching || _isEmergencyFallback || _isOfflineError) return; 
    
    setState(() => _isSwitching = true);
    await webViewController?.stopLoading();

    if (_currentUrlIndex < widget.urls.length - 1) {
      _currentUrlIndex++;
      final nextUrl = widget.urls[_currentUrlIndex];
      await _injectSecurityToken(nextUrl);
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(nextUrl)));
      if (mounted) setState(() => _isSwitching = false);
    } else {
      if (mounted) setState(() => _isEmergencyFallback = true);
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
        secondaryApp = await Firebase.initializeApp(name: 'SecondaryFallbackApp', options: secondaryOptions);
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
        final builtError = 'تعذر الاتصال بالخوادم الآمنة.\n\n[P]: $primaryErrorText\n\n[S]: $secondaryError';
        if (builtError.contains('remote config fetch error') || builtError.contains('ClientException') || builtError.contains('network_error')) {
           setState(() => _isOfflineError = true);
           return;
        }
        setState(() {
          _isTotalFailure = true;
          _errorMessage = builtError;
        });
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

    DateTime? currentBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // منع الخروج الافتراضي المباشر
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // 1. الأولوية للتصفح العكسي داخل موقع Flutter Web
        if (webViewController != null && !_isOfflineError && !_isTotalFailure) {
          if (await webViewController!.canGoBack()) {
             await webViewController!.goBack();
             return; // إيقاف تنفيذ الخروج لأن المستخدم عاد للخلف داخل الموقع
          }
        }
        
        // 2. محرك النقر المزدوج للخروج النهائي (Double-Tap to Exit)
        DateTime now = DateTime.now();
        if (currentBackPressTime == null || now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
          currentBackPressTime = now;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'انقر مرة أخرى للخروج من التطبيق',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
                backgroundColor: Colors.blueGrey.shade900,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
              ),
            );
          }
        } else {
          // الخروج النهائي والفوري من التطبيق
          SystemNavigator.pop();
        }
      },
      child: _buildContent(context),
    );
  }

  // الدالة الأساسية المعمارية (تم إعادة تسميتها للحفاظ على الأكواد السابقة 100%)
  Widget _buildContent(BuildContext context) {
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

    if (_isInitializing || _isEmergencyFallback) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
    }

    // 🛡️ معمارية الطبقات المتراكبة (Stack Architecture) لضمان عدم إتلاف حالة المتصفح
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // الطبقة الأولى: المتصفح (يبقى حياً دائماً في الخلفية ولا يتم تدميره أبداً)
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
              onReceivedError: (controller, request, error) async {
                if (request.isForMainFrame == true) {
                  debugPrint('⚠️ خطأ في تحميل المورد أو الشبكة: ${error.description}');
                  _mainFrameFailed = true; // تأكيد انهيار الصفحة الفعلي
                  if (mounted) setState(() => _isOfflineError = true);
                }
              },
              onReceivedHttpError: (controller, request, errorResponse) async {
                if (request.isForMainFrame == true) {
                  _handleMainFrameError();
                }
              },
            ),
            
            // الطبقة الثانية: منع الوميض عند تغيير الروابط
            if (_isSwitching) Container(color: Colors.black), 
            
                        // الطبقة الثالثة العلوية: واجهة العزل البصرية (تغطي المتصفح دون أن تدمره)
            if (_isOfflineError)
              Container(
                color: Colors.black, // حجب بصري تام
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : const Text('إعادة المحاولة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
