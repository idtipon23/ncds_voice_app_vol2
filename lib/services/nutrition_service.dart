import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

class NutritionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final GenerativeModel _model;

  NutritionService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  /// 🎙️ 1. AI วิเคราะห์อาหารจาก "ไฟล์เสียงพูด" (Multimodal Audio)
  Future<Map<String, dynamic>?> analyzeFoodFromAudio({
    required File audioFile,
    required String underlyingDiseases,
  }) async {
    final now = DateTime.now();
    final isLateNight = now.hour >= 20 || now.hour < 4;

    final prompt = '''
คุณคือนักโภชนาการทางการแพทย์สำหรับผู้ป่วยโรคเรื้อรัง (NCDs)
จงฟังเสียงบันทึกของผู้ป่วย แล้ววิเคราะห์รายการอาหารและเครื่องดื่มที่ผู้ป่วยพูด

ข้อมูลผู้ป่วย:
- โรคประจำตัว: $underlyingDiseases
- เวลาที่รับประทานปัจจุบัน: ${now.hour}:${now.minute.toString().padLeft(2, '0')} น. (ช่วงหลัง 20.00 น. = $isLateNight)

กรุณาถอดเสียงเป็นชื่ออาหาร คำนวณสารอาหารโดยอ้างอิงจากฐานข้อมูลอาหารไทยและอาหารร้านสะดวกซื้อ และส่งกลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "food_name": "ชื่ออาหารทั้งหมดที่ผู้ป่วยพูด เช่น ข้าวกะเพราหมูกรอบไข่ดาว และ ชาไทยหวานน้อย",
  "calories": 450.0,
  "carbs_g": 55.0,
  "protein_g": 20.0,
  "fat_g": 16.0,
  "sodium_mg": 850.0,
  "sugar_g": 15.0,
  "trans_fat_g": 0.0,
  "fiber_g": 2.5,
  "meal_type": "มื้ออาหาร",
  "warning_flags": [
    "ข้อความเตือนทางการแพทย์ เช่น โซเดียมสูงเกิน 600mg (ระวังในโรคความดัน/ไต), น้ำตาลสูง (ระวังในเบาหวาน), ไขมันทรานส์, หรือทานมื้อดึกหลัง 20.00 น."
  ],
  "nutrition_advice": "คำแนะนำสั้นๆ 1 ประโยคสำหรับมื้อนี้"
}
''';

    try {
      final audioBytes = await audioFile.readAsBytes();
      final String mimeType =
          audioFile.path.endsWith('.wav') ? 'audio/wav' : 'audio/m4a';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, audioBytes),
        ]),
      ];

      final response = await _model.generateContent(content);
      if (response.text != null) {
        return jsonDecode(response.text!) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('❌ Gemini Audio Nutrition Error: $e');
    }
    return null;
  }

  /// 📝 2. AI วิเคราะห์อาหารจาก "ข้อความพิมพ์"
  Future<Map<String, dynamic>?> analyzeFoodInput({
    required String textInput,
    required String underlyingDiseases,
  }) async {
    final now = DateTime.now();
    final isLateNight = now.hour >= 20 || now.hour < 4;

    final prompt = '''
คุณคือนักโภชนาการทางการแพทย์สำหรับผู้ป่วยโรคเรื้อรัง (NCDs)
จงวิเคราะห์เมนูอาหารต่อไปนี้: "$textInput"

ข้อมูลผู้ป่วย:
- โรคประจำตัว: $underlyingDiseases
- เวลาที่รับประทานปัจจุบัน: ${now.hour}:${now.minute.toString().padLeft(2, '0')} น. (ช่วงหลัง 20.00 น. = $isLateNight)

กรุณาคำนวณสารอาหารโดยอ้างอิงจากฐานข้อมูลอาหารไทยและอาหารร้านสะดวกซื้อ และส่งกลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "food_name": "ชื่ออาหารที่ระบุ",
  "calories": 350.0,
  "carbs_g": 45.0,
  "protein_g": 18.0,
  "fat_g": 12.0,
  "sodium_mg": 850.0,
  "sugar_g": 6.0,
  "trans_fat_g": 0.0,
  "fiber_g": 3.0,
  "meal_type": "มื้ออาหาร",
  "warning_flags": [
    "ข้อความเตือนถ้ามี เช่น โซเดียมสูงเกิน 600mg (ระวังในโรคความดัน/ไต), มีน้ำตาลสูง (ระวังในเบาหวาน), มีไขมันทรานส์, หรือทานมื้อดึกหลัง 20.00 น."
  ],
  "nutrition_advice": "คำแนะนำสั้นๆ 1 ประโยคสำหรับมื้อนี้"
}
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      if (response.text != null) {
        return jsonDecode(response.text!) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('❌ Gemini Text Nutrition Error: $e');
    }
    return null;
  }

  /// 💾 3. บันทึกมื้ออาหารลง Supabase
  Future<void> saveFoodLog({
    required String patientId,
    required Map<String, dynamic> foodData,
  }) async {
    await _supabase.from('food_logs').insert({
      'patient_id': patientId,
      'food_name': foodData['food_name'] ?? 'อาหาร',
      'calories': foodData['calories'] ?? 0.0,
      'carbs_g': foodData['carbs_g'] ?? 0.0,
      'protein_g': foodData['protein_g'] ?? 0.0,
      'fat_g': foodData['fat_g'] ?? 0.0,
      'sodium_mg': foodData['sodium_mg'] ?? 0.0,
      'sugar_g': foodData['sugar_g'] ?? 0.0,
      'trans_fat_g': foodData['trans_fat_g'] ?? 0.0,
      'fiber_g': foodData['fiber_g'] ?? 0.0,
      'meal_type': foodData['meal_type'] ?? 'มื้ออาหาร',
      'warning_flags': foodData['warning_flags'] ?? [],
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// 💾 4. บันทึกการออกกำลังกายลง Supabase
  Future<void> saveExerciseLog({
    required String patientId,
    required String exerciseName,
    required int durationMinutes,
    required double caloriesBurned,
  }) async {
    await _supabase.from('exercise_logs').insert({
      'patient_id': patientId,
      'exercise_name': exerciseName,
      'duration_minutes': durationMinutes,
      'calories_burned': caloriesBurned,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// 📊 5. ดึงบันทึกอาหารของวันนี้
  Future<List<Map<String, dynamic>>> getTodayFoodLogs(String patientId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final res = await _supabase
        .from('food_logs')
        .select()
        .eq('patient_id', patientId)
        .eq('logged_date', today)
        .order('recorded_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// 🏃‍♂️ 6. ดึงบันทึกออกกำลังกายของวันนี้
  Future<List<Map<String, dynamic>>> getTodayExerciseLogs(
      String patientId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final res = await _supabase
        .from('exercise_logs')
        .select()
        .eq('patient_id', patientId)
        .eq('logged_date', today)
        .order('recorded_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }
}
