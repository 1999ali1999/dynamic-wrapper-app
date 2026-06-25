import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;

class FallbackScreen extends StatefulWidget {
  final Map<String, dynamic> config;
  const FallbackScreen({super.key, required this.config});

  @override
  State<FallbackScreen> createState() => _FallbackScreenState();
}

// 🛡️ دمج WidgetsBindingObserver لمراقبة دورة حياة التطبيق
class _FallbackScreenState extends State<FallbackScreen> with WidgetsBindingObserver {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  
  // متغيرات التحكم والإلغاء
  http.Client? _httpClient;
  bool _isCancelled = false;
  String? _downloadedFilePath;
  bool _isInstalling = false; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanUpOldFiles(); // تنظيف استباقي للذاكرة عند فتح الشاشة
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _httpClient?.close();
    super.dispose();
  }

  // 🛡️ مستشعر العودة: يمسح الملف بمجرد انتهاء المستخدم من التثبيت وعودته للتطبيق
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isInstalling && _downloadedFilePath != null) {
      _deleteFile(_downloadedFilePath!);
      _isInstalling = false;
      if (mounted) {
        setState(() {
          _statusMessage = 'تم تثبيت التحديث وتنظيف الذاكرة المؤقتة بنجاح.';
        });
      }
    }
  }

  Future<void> _cleanUpOldFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/app_update.apk'); 
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ تم تدمير ملف التحديث لتفريغ الذاكرة (Cache Bloat Cleared): $path');
      }
    } catch (_) {}
  }

  // محرك الإلغاء الفوري
  void _cancelDownload() {
    setState(() {
      _isCancelled = true;
      _isDownloading = false;
      _statusMessage = 'تم إلغاء التنزيل.';
    });
    _httpClient?.close(); // قطع الاتصال بالخادم فوراً
    if (_downloadedFilePath != null) {
      _deleteFile(_downloadedFilePath!); // تدمير الملف غير المكتمل
    }
  }

  Future<void> _startDirectDownload() async {
    setState(() {
      _isCancelled = false;
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'جاري الاتصال بخادم التحديث...';
    });

    try {
      String? downloadUrl;
      String fileName = 'update_file';
      
      if (Platform.isAndroid) {
        downloadUrl = widget.config['android_url'];
        fileName = 'app_update.apk';
      } else if (Platform.isWindows) {
        downloadUrl = widget.config['windows_url'];
        fileName = 'app_update.exe';
      } else if (Platform.isMacOS) {
        downloadUrl = widget.config['macos_url'];
        fileName = 'app_update.dmg';
      } else if (Platform.isLinux) {
        downloadUrl = widget.config['linux_url'];
        fileName = 'app_update.tar.gz';
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('رابط التحميل المباشر غير متوفر لهذا النظام.');
      }

      final dir = await getTemporaryDirectory();
      _downloadedFilePath = '${dir.path}/$fileName';
      final file = File(_downloadedFilePath!);

      if (await file.exists()) await file.delete();

      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await _httpClient!.send(request);

      if (response.statusCode != 200) {
         throw Exception('الخادم رفض الطلب: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen((List<int> chunk) {
        if (_isCancelled) return; // إيقاف الكتابة إذا تم النقر على إلغاء
        downloadedBytes += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          setState(() {
            _downloadProgress = downloadedBytes / contentLength;
            _statusMessage = 'جاري التنزيل: ${(_downloadProgress * 100).toStringAsFixed(1)}%';
          });
        } else {
          setState(() {
            _statusMessage = 'جاري التنزيل...';
          });
        }
      }).asFuture();

      await sink.close();
      _httpClient?.close();

      if (_isCancelled) {
         await _deleteFile(_downloadedFilePath!);
         return;
      }

      setState(() {
        _statusMessage = 'اكتمل التنزيل. جاري الإعداد للتثبيت...';
        _isDownloading = false;
        _isInstalling = true; // تفعيل مستشعر الانتظار لعودة التطبيق
      });

      final result = await OpenFilex.open(_downloadedFilePath!);
      if (result.type != ResultType.done) {
         throw Exception('تعذر فتح ملف التحديث تلقائياً.');
      }

    } catch (e) {
      if (!_isCancelled) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'حدث خطأ: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_rounded, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 20),
                const Text(
                  'عليك ترقية التطبيق الآن',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                if (_isDownloading) ...[
                  LinearProgressIndicator(
                    value: _downloadProgress, 
                    backgroundColor: Colors.grey.shade300, 
                    color: Colors.blueAccent,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 15),
                  Text(_statusMessage, style: const TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center, textDirection: TextDirection.rtl),
                  const SizedBox(height: 20),
                  // 🛡️ زر إلغاء التنزيل الجديد
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.shade100,
                      foregroundColor: Colors.red.shade900,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.cancel_rounded),
                    label: const Text('إلغاء التنزيل'),
                    onPressed: _cancelDownload,
                  ),
                ] else ...[
                  if (_statusMessage.isNotEmpty) ...[
                    Text(_statusMessage, style: TextStyle(fontSize: 14, color: _statusMessage.contains('تم') ? Colors.green.shade700 : Colors.redAccent), textAlign: TextAlign.center, textDirection: TextDirection.rtl),
                    const SizedBox(height: 15),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87, elevation: 0),
                        onPressed: () => exit(0),
                        child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, elevation: 2),
                        onPressed: _startDirectDownload,
                        child: const Text('تنزيل', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
