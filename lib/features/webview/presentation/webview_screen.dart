import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

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

  @override
  void initState() {
    super.initState();
    // إعدادات الأداء القصوى والتوافق
    settings = InAppWebViewSettings(
      transparentBackground: true, 
      hardwareAcceleration: true,  
      javaScriptEnabled: true,
      cacheEnabled: true,
      useShouldInterceptRequest: false, 
      supportMultipleWindows: false,
    );
  }

  // الحقن الأمني الصامت قبل التحميل
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder(
          future: _injectSecurityToken(widget.urls[_currentUrlIndex]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink(); 
            }

            return InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.urls[_currentUrlIndex]),
              ),
              initialSettings: settings,
              onWebViewCreated: (controller) async {
                webViewController = controller;
                
                // ==========================================
                // الكشف التلقائي: إظهار النافذة المخفية فور جهوزية المحرك
                // ==========================================
                if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
                  await windowManager.show();
                  await windowManager.focus(); // وضع النافذة في مقدمة الشاشة
                }
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                if (request.url.toString() == widget.urls[_currentUrlIndex]) {
                  _switchToNextUrl();
                }
              },
              onReceivedError: (controller, request, error) {
                 if (request.url.toString() == widget.urls[_currentUrlIndex]) {
                  _switchToNextUrl();
                }
              },
            );
          }
        ),
      ),
    );
  }

  void _switchToNextUrl() async {
    if (_currentUrlIndex < widget.urls.length - 1) {
      _currentUrlIndex++;
      final nextUrl = widget.urls[_currentUrlIndex];
      debugPrint('🔄 تحويل صامت إلى الاستضافة البديلة: $nextUrl');
      
      await _injectSecurityToken(nextUrl);
      
      webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(nextUrl))
      );
    } else {
      debugPrint('❌ جميع روابط الاستضافة فشلت.');
    }
  }
}
