import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ฟังก์ชันจำลอง (Stub) เพื่อไม่ให้ Error 'getAuthService'
AuthService getAuthService() => AuthService();

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ฟังก์ชันเดิมของพี่ชาย
  Future<AuthResponse> signInAnonymouslyIfNeeded() async {
    try {
      if (_supabase.auth.currentSession != null) {
        return AuthResponse(
          session: _supabase.auth.currentSession,
          user: _supabase.auth.currentUser,
        );
      }
      return await _supabase.auth.signInAnonymously();
    } catch (e) {
      print('Error signing in anonymously: $e');
      rethrow;
    }
  }

  // เพิ่มฟังก์ชันหลอกสำหรับ LINE SDK เพื่อให้ผ่านการคอมไพล์
  Future<void> initLineSdk({required String? channelId, required String? liffId}) async {
    debugPrint('initLineSdk called with channelId: $channelId, liffId: $liffId');
    // อนาคตถ้าจะเชื่อม LINE LIFF จริงๆ ค่อยมาเขียนโค้ดตรงนี้เพิ่มครับ
  }

  // เพิ่มฟังก์ชันหลอกสำหรับการล็อกอิน LINE เพื่อให้ผ่านการคอมไพล์
  Future<AuthResponse?> signInWithLine() async {
    debugPrint('signInWithLine called (Mock)');
    // ตอนนี้ให้จำลองการล็อกอินแบบ Anonymous ไปก่อน เพื่อให้เข้าแอปได้
    return await signInAnonymouslyIfNeeded();
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  User? get currentUser => _supabase.auth.currentUser;
}