import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthStrategy {
  // 📍 แก้ไขบรรทัดนี้ให้เป็น Named Parameters เพื่อให้รับได้ทั้ง 2 ค่า
  Future<void> initLineSdk({String? channelId, String? liffId});
  
  Future<AuthResponse?> signInWithLine();
  Future<void> signOut();
  User? get currentUser;
}