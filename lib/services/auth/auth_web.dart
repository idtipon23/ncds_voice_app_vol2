import 'dart:js' as js; // 📍 นำเข้า dart:js สำหรับคุยกับ JavaScript (LIFF SDK)
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_interface.dart';

class AuthServiceImpl implements AuthStrategy {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // 📍 ตัวแปรเก็บสถานะว่า LIFF พร้อมใช้งานหรือยัง
  bool _isLiffInitialized = false;

  @override
  Future<void> initLineSdk({String? channelId, String? liffId}) async {
    try {
      if (liffId == null || liffId.isEmpty) {
        throw Exception('ไม่ได้ระบุ LIFF ID ในไฟล์ .env');
      }

      debugPrint('🌐 [WEB] กำลัง Initialize LINE LIFF...');
      
      // 📍 เรียกใช้คำสั่ง liff.init() ฝั่ง JavaScript โดยส่ง liffId ที่ได้จาก .env
      final promise = js.context['liff'].callMethod('init', [
        js.JsObject.jsify({'liffId': liffId})
      ]);
      
      // รอให้ LIFF Init เสร็จ
      await js.context['Promise'].callMethod('resolve', [promise]);
      _isLiffInitialized = true;
      debugPrint('✅ [WEB] LINE LIFF Initialized สำเร็จ!');
      
    } catch (e) {
      debugPrint('❌ [WEB] LINE LIFF Init Error: $e');
    }
  }

  @override
  Future<AuthResponse?> signInWithLine() async {
    try {
      if (!_isLiffInitialized) {
        throw Exception('LIFF ยังไม่พร้อมทำงาน กรุณารอสักครู่แล้วลองใหม่');
      }

      debugPrint('🌐 [WEB] กำลังเข้าสู่ระบบผ่าน LIFF...');

      // 📍 1. เช็กว่าผู้ใช้ล็อกอินผ่าน LINE (ในเบราว์เซอร์หรือแอป LINE) หรือยัง
      final isLoggedIn = js.context['liff'].callMethod('isLoggedIn');

      if (!isLoggedIn) {
        // ถ้ายังไม่ได้ล็อกอิน ให้พาไปหน้าล็อกอินของ LINE
        debugPrint('🌐 [WEB] ยังไม่ได้ล็อกอิน เด้งไปหน้า LINE Login...');
        js.context['liff'].callMethod('login');
        return null; // หยุดการทำงานชั่วคราว เพราะเว็บจะโดน Redirect ไปหน้าล็อกอิน
      }

      // 📍 2. ถ้าล็อกอินแล้ว ให้ดึง Profile ออกมา (เอา userId ของจริง)
      debugPrint('🌐 [WEB] ล็อกอินแล้ว กำลังดึง Profile...');
      final profilePromise = js.context['liff'].callMethod('getProfile');
      final jsProfile = await js.context['Promise'].callMethod('resolve', [profilePromise]);
      
      // ดึง userId ออกมาจาก Object ที่ LINE คืนมา
      final lineUserId = jsProfile['userId'].toString();
      debugPrint('✅ [WEB] ได้ LINE ID: $lineUserId');

      // 📍 3. นำ LINE ID ของจริงมาสร้าง Shadow Account ทะลวงเข้า Supabase
      final shadowEmail = '$lineUserId@ncd-app.local';
      final shadowPassword = 'NCD_${lineUserId}_Secure99!';

      try {
        debugPrint('กำลังเข้าสู่ระบบ Shadow Account (Web)...');
        return await _supabase.auth.signInWithPassword(
          email: shadowEmail,
          password: shadowPassword,
        );
      } catch (e) {
        debugPrint('ไม่พบข้อมูลเดิม กำลังลงทะเบียน Shadow Account ใหม่ (Web)...');
        return await _supabase.auth.signUp(
          email: shadowEmail,
          password: shadowPassword,
        );
      }
    } catch (e) {
      debugPrint('❌ Web Auth Error: $e');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_isLiffInitialized) {
        // ล็อกเอาต์ออกจากระบบของ LINE LIFF ด้วย
        js.context['liff'].callMethod('logout');
      }
      // ล็อกเอาต์ออกจาก Supabase
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Web Logout Error: $e');
    }
  }

  @override
  User? get currentUser => _supabase.auth.currentUser;
}

AuthStrategy getAuthService() => AuthServiceImpl();