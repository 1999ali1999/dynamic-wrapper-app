import 'package:flutter_test/flutter_test.dart';
// سيتم قراءة المشروع بناءً على الاسم المعرف في pubspec.yaml
import 'package:dynamic_wrapper_app/main.dart';
import 'package:dynamic_wrapper_app/features/splash/presentation/splash_handler.dart';

void main() {
  testWidgets('تحقق من تحميل التطبيق (MainApp) وظهور الشاشة الشفافة (SplashHandler) بنجاح', (WidgetTester tester) async {
    // بناء التطبيق الخاص بنا بالاسم المعماري الصحيح
    await tester.pumpWidget(const MainApp());

    // التحقق من عدم وجود أخطاء وأن واجهة SplashHandler الشفافة موجودة بالفعل
    expect(find.byType(SplashHandler), findsOneWidget);
  });
}
