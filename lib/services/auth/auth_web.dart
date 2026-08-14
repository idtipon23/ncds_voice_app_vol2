// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_interface.dart';

class AuthServiceImpl implements AuthStrategy {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLiffInitialized = false;

  @override
  Future<void> initLineSdk({String? channelId, String? liffId}) async {
    try {
      if (liffId == null || liffId.isEmpty) {
        throw Exception('ไม่ได้ระบุ LIFF ID ในไฟล์ .env');
      }

      debugPrint('🌐 [WEB] กำลัง Initialize LINE LIFF...');

      // ตรวจสอบว่าใน index.html โหลด LIFF SDK เข้ามาหรือยัง
      if (!globalContext.has('liff')) {
        throw Exception(
            'ไม่พบ LINE LIFF SDK กรุณาตรวจสอบว่ามี <script src="https://static.line-scdn.net/liff/edge/2/sdk.js"></script> ใน web/index.html หรือไม่');
      }

      final liff = globalContext['liff'] as JSObject;
      final config = JSObject();
      config['liffId'] = liffId.toJS;

      // เรียก liff.init() และแปลง JS Promise เป็น Dart Future ด้วยมาตรฐาน js_interop
      final initPromise = liff.callMethod<JSPromise>('init'.toJS, config);
      await initPromise.toDart;

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

      final liff = globalContext['liff'] as JSObject;
      final isLoggedIn = (liff.callMethod<JSBoolean>('isLoggedIn'.toJS)).toDart;

      if (!isLoggedIn) {
        debugPrint('🌐 [WEB] ยังไม่ได้ล็อกอิน เด้งไปหน้า LINE Login...');
        liff.callMethod('login'.toJS);
        return null; // หน้าเว็บจะถูก Redirect ไปที่ LINE Login
      }

      debugPrint('🌐 [WEB] ล็อกอินแล้ว กำลังดึง Profile...');
      final profilePromise = liff.callMethod<JSPromise>('getProfile'.toJS);
      final jsProfile = (await profilePromise.toDart) as JSObject;

      final userIdObj = jsProfile['userId'];
      if (userIdObj == null) {
        throw Exception('ไม่สามารถอ่านค่า userId จาก Profile ได้');
      }

      final lineUserId = (userIdObj as JSString).toDart;
      debugPrint('✅ [WEB] ได้ LINE ID: $lineUserId');

      // สร้าง Shadow Account สำหรับ Supabase
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
      if (_isLiffInitialized && globalContext.has('liff')) {
        final liff = globalContext['liff'] as JSObject;
        liff.callMethod('logout'.toJS);
      }
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Web Logout Error: $e');
    }
  }

  @override
  User? get currentUser => _supabase.auth.currentUser;
}

AuthStrategy getAuthService() => AuthServiceImpl();