import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientProfileService {
  static const String _patientIdKey = 'current_patient_id';
  static const String _profileKey = 'patient_profile_data';
  static const String _isRegisteredKey = 'is_registered';
  static const String _onboardedKey = 'is_onboarded';
  
  // 📍 คีย์หลักสำหรับระบบ Smart HN Memory
  static const String _lastHnKey = 'last_used_hn';
  static const String _lastHospitalIdKey = 'last_used_hospital_id';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// ดึง ID ผู้ป่วยปัจจุบัน (ลำดับความสำคัญ: ID ที่ผูกสำเร็จ -> Auth User ID -> Local ID)
  Future<String?> getCurrentPatientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? localId = prefs.getString(_patientIdKey);
    if (localId != null && localId.isNotEmpty) {
      return localId;
    }
    return null;
  }

  /// 📍 ตรวจสอบว่าโปรไฟล์มีข้อมูล HN และ hospital_id สมบูรณ์หรือไม่
  bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final hn = profile['hn']?.toString() ?? '';
    final hospitalId = profile['hospital_id']?.toString() ?? '';
    return profile['id'] != null && hn.isNotEmpty && hospitalId.isNotEmpty;
  }

  /// 📍 ฟังก์ชันดึงโปรไฟล์อัจฉริยะ (ดึงประวัติยาและข้อมูลทันทีหากเครื่องจำ HN ได้)
  Future<Map<String, dynamic>?> validateAndLoadProfile() async {
    final currentUser = _supabase.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    try {
      // 1. ระบบAuto lockin ตรวจสอบเบื้องหลังด้วย Auth User ID ก่อน
      /*
      if (currentUser != null) {
        final data = await _supabase
            .from('patients')
            .select()
            .eq('id', currentUser.id)
            .maybeSingle();

        if (data != null && isProfileComplete(data)) {
          await _saveSmartMemory(
            patientId: currentUser.id,
            hn: data['hn'].toString(),
            hospitalId: data['hospital_id'].toString(),
            profileData: data,
          );
          return data;
        }
      }
      */

      // 2. 🚀 ดึงจาก Smart HN Memory ในเครื่องทันที! (ทำให้ไม่ต้องลงทะเบียน HN ใหม่)
      final cachedHn = prefs.getString(_lastHnKey);
      final cachedHospitalId = prefs.getString(_lastHospitalIdKey);

      if (cachedHn != null && cachedHn.isNotEmpty && cachedHospitalId != null && cachedHospitalId.isNotEmpty) {
        final cachedData = await _supabase
            .from('patients')
            .select()
            .eq('hn', cachedHn)
            .eq('hospital_id', cachedHospitalId)
            .maybeSingle();

        if (cachedData != null && isProfileComplete(cachedData)) {
          // ดึงเจอข้อมูลผู้ป่วยเดิม -> บันทึกการผูกสิทธิ์แล้วคืนค่าข้อมูลทันที!
          await _saveSmartMemory(
            patientId: cachedData['id'].toString(),
            hn: cachedHn,
            hospitalId: cachedHospitalId,
            profileData: cachedData,
          );
          return cachedData;
        }
      }

      // 3. อ่านจาก Cache สำรองในเครื่องกรณีไม่มีเน็ต
      final cachedProfile = await getProfile();
      if (cachedProfile != null && isProfileComplete(cachedProfile)) {
        return cachedProfile;
      }

      return null; // จะส่งไปหน้าลงทะเบียนเฉพาะเคสที่ไม่เคยมี HN ในระบบจริง ๆ เท่านั้น
    } catch (e) {
      debugPrint('⚠️ Error validating profile: $e');
      return await getProfile();
    }
  }

  /// บันทึกข้อมูลโปรไฟล์และความจำ HN ลงเครื่อง
  Future<void> _saveSmartMemory({
    required String patientId,
    required String hn,
    required String hospitalId,
    required Map<String, dynamic> profileData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_patientIdKey, patientId);
    await prefs.setString(_lastHnKey, hn);
    await prefs.setString(_lastHospitalIdKey, hospitalId);
    await prefs.setString(_profileKey, jsonEncode(profileData));
    await prefs.setBool(_isRegisteredKey, true);
  }

  Future<void> saveExistingSession(Map<String, dynamic> patientData) async {
    final patientId = patientData['id'].toString();
    final hn = patientData['hn']?.toString() ?? '';
    final hospitalId = patientData['hospital_id']?.toString() ?? '';

    await _saveSmartMemory(
      patientId: patientId,
      hn: hn,
      hospitalId: hospitalId,
      profileData: patientData,
    );
  }

  Future<void> updateLocalProfile(Map<String, dynamic> newData) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = await getProfile() ?? {};
    
    currentProfile.addAll(newData);
    await prefs.setString(_profileKey, jsonEncode(currentProfile));

    final patientId = await getCurrentPatientId();
    if (patientId != null && patientId.isNotEmpty) {
      try {
        final Map<String, dynamic> updatePayload = {};
        if (newData.containsKey('age')) updatePayload['age'] = newData['age'];
        if (newData.containsKey('weight')) updatePayload['weight'] = newData['weight'];
        if (newData.containsKey('height')) updatePayload['height'] = newData['height'];
        if (newData.containsKey('diseases')) updatePayload['underlying_diseases'] = newData['diseases'];
        if (newData.containsKey('takesMedication')) updatePayload['takes_medication'] = newData['takesMedication'];
        if (newData.containsKey('smokes')) updatePayload['smokes'] = newData['smokes'];
        if (newData.containsKey('drinksAlcohol')) updatePayload['drinks_alcohol'] = newData['drinksAlcohol'];

        if (updatePayload.isNotEmpty) {
          await _supabase.from('patients').update(updatePayload).eq('id', patientId);
        }
      } catch (e) {
        debugPrint('⚠️ Error Syncing to Supabase: $e');
      }
    }
  }

  Future<void> updateProfileData(Map<String, dynamic> newData) async => updateLocalProfile(newData);

  Future<Map<String, dynamic>?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String? profileStr = prefs.getString(_profileKey);

    // 1. ลองดึงจาก Local Storage (กรณีใช้งานปกติ)
    if (profileStr != null && profileStr.isNotEmpty) {
      try {
        return jsonDecode(profileStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('⚠️ Error decoding cached profile: $e');
      }
    }

    // 2. 📍 [เพิ่มใหม่]: กู้คืนข้อมูลจาก Supabase กรณีลบแอป / Cache หาย
    try {
      final patientId = await getCurrentPatientId();
      if (patientId != null) {
        final response = await _supabase
            .from('patients')
            .select()
            .eq('id', patientId)
            .maybeSingle();

        if (response != null) {
          // 3. 📍 เซฟข้อมูลกลับลงเครื่องแบบเนียนๆ (Self-Healing)
          await prefs.setString(_profileKey, jsonEncode(response));
          await prefs.setString(_patientIdKey, patientId);
          
          if (response['hn'] != null) {
            await prefs.setString(_lastHnKey, response['hn'].toString());
          }
          if (response['hospital_id'] != null) {
            await prefs.setString(_lastHospitalIdKey, response['hospital_id'].toString());
          }
          
          debugPrint('✅ กู้คืนโปรไฟล์ผู้ป่วยและ HN สำเร็จ!');
          return response;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching profile from Supabase: $e');
    }

    return null;
  }

  Future<Map<String, String>> getLastLoginInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'hn': prefs.getString(_lastHnKey) ?? '',
      'hospital_id': prefs.getString(_lastHospitalIdKey) ?? '',
    };
  }

  Future<String> getProfilePromptContext() async {
    final profile = await getProfile();
    if (profile == null) return '[ไม่พบข้อมูลโปรไฟล์ผู้ป่วย]';
    return '''
[บริบทประจำตัวผู้ป่วย (User Profile Context)]
- ID: ${profile['id'] ?? 'N/A'}
- HN: ${profile['hn'] ?? 'N/A'}
- อายุ: ${profile['age'] ?? 'ไม่ระบุ'} ปี
- น้ำหนัก: ${profile['weight'] ?? 'ไม่ระบุ'} กก.
- ส่วนสูง: ${profile['height'] ?? 'ไม่ระบุ'} ซม.
- โรคประจำตัว: ${profile['underlying_diseases'] ?? profile['diseases'] ?? 'ไม่มี'}
''';
  }

  Future<void> clearLocalIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_patientIdKey);
    await prefs.remove(_profileKey);
    await prefs.setBool(_isRegisteredKey, false);
    await prefs.setBool(_onboardedKey, false);
    await prefs.remove(_lastHnKey);
    await prefs.remove(_lastHospitalIdKey);
    await _supabase.auth.signOut();
  }

  Future<void> fullLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _supabase.auth.signOut();
  }
  /// 📍 บันทึกข้อมูลโปรไฟล์และ Smart HN ลงความจำเครื่อง
  Future<void> saveProfile(Map<String, dynamic> profileData) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. บันทึก ID ผู้ป่วย (Patient UUID)
    if (profileData['id'] != null) {
      await prefs.setString(_patientIdKey, profileData['id'].toString());
    }
    
    // 2. บันทึก Smart HN Memory (จำรหัสเพื่อ Auto-fill ครั้งหน้า)
    if (profileData['hn'] != null) {
      await prefs.setString(_lastHnKey, profileData['hn'].toString());
    }
    if (profileData['hospital_id'] != null) {
      await prefs.setString(_lastHospitalIdKey, profileData['hospital_id'].toString());
    }
    
    // 3. บันทึกข้อมูล Profile ทั้งหมดเป็น JSON
    await prefs.setString(_profileKey, jsonEncode(profileData));
    
    // 4. อัปเดตสถานะว่าเข้าสู่ระบบและลงทะเบียนแล้ว
    await prefs.setBool(_isRegisteredKey, true);
    await prefs.setBool(_onboardedKey, true);
  }

}