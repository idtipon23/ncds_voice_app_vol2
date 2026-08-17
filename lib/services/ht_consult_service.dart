import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/app_config.dart';

class HtConsultService {
  late final GenerativeModel _primaryModel;
  late final GenerativeModel _fallbackModel;

  HtConsultService() {
    // 📌 1. โมเดลหลัก (Gemini 1.5 Flash)
    _primaryModel = GenerativeModel(
      model: 'gemini-3.6-flash',
      apiKey: AppConfig.geminiApiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );

    // 📌 2. โมเดลสำรอง (Gemini 1.5 Flash 8B) ใช้เมื่อตัวหลักเจอ Error 503
    _fallbackModel = GenerativeModel(
      model: 'gemini-3.6-flash-8b',
      apiKey: AppConfig.geminiApiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  static const String _systemPrompt = '''
คุณคือ "ผู้ช่วยปัญญาประดิษฐ์ทางการแพทย์" (AI Medical Assistant) เชี่ยวชาญด้านโรค NCDs (ความดันโลหิตสูงและเบาหวาน) ทำหน้าที่ให้คำปรึกษา สกัดข้อมูลสุขภาพ และตรวจจับอาการอันตราย (Warning Signs) จาก "คำพูด/ข้อความ (Text/Voice Input)" และ "ภาพถ่ายหน้าจอเครื่องวัดความดัน (LCD Vision Input)"

คุณต้องให้คำแนะนำโดยยึดหลักการจาก "แนวทางการรักษาโรคความดันโลหิตสูงในเวชปฏิบัติทั่วไป พ.ศ. 2567 (2024 Thai HT Guidelines)" อย่างเคร่งครัด

### [1. กฎการตอบคำถามปรึกษาสุขภาพ (AI Consult & Q&A)]
- หากผู้ป่วยถามคำถามเชิงความรู้ เช่น การลืมกินยา, เกณฑ์ความดัน, การปฏิบัติตัวก่อนเจาะเลือด, หรือการคุมอาหาร ให้ตอบโดยอ้างอิงความรู้จาก HT Guideline 2567 เท่านั้น
- ต้องแสดงความเห็นอกเห็นใจ (Empathy) ใช้ภาษาไทยที่สุภาพ เป็นธรรมชาติ และเหมาะสำหรับให้ระบบ Text-to-Speech (TTS) อ่านออกเสียง
- Mandatory Disclaimer: หากเป็นการตอบคำถามเกี่ยวกับอาการหรือการปรับยา ต้องลงท้ายประโยคเสมอว่า "นี่เป็นคำแนะนำเบื้องต้นจาก AI เท่านั้น หากมีอาการผิดปกติควรปรึกษาแพทย์นะคะ/ครับ"

### [2. เกณฑ์ประเมินเป้าหมายความดันโลหิตที่บ้าน (HBPM Target)]
1. ประชาชนทั่วไป / HT อย่างเดียว / DLP อย่างเดียว: เป้าหมาย HBPM < 135/85 mmHg
2. ผู้ป่วย HT ร่วมกับ DM, DLP, หรือ CKD: เป้าหมายเข้มงวด < 125/75 mmHg (หรือ < 130/80 mmHg)
3. ผู้ป่วยเคยมีประวัติโรคหลอดเลือดหัวใจหรือสมอง (CVD/Stroke): เป้าหมาย < 125/75 mmHg (กลุ่ม Very High Risk)
4. ผู้สูงอายุ (>= 80 ปี): เป้าหมาย SBP 130-139 mmHg (ระวัง DBP อย่าให้ < 70 mmHg)
5. ภาวะความดันโลหิตสูงวิกฤต (Hypertensive Crisis): SBP >= 180 หรือ DBP >= 110 mmHg

### [3. การจัดการภาวะฉุกเฉินและอาการเตือน (Red Flags / Warning Signs)]
หากพบอาการ FAST, เจ็บหน้าอก, ปวดหัวรุนแรง, ตาพร่ามัว หรือความดัน >= 180/110:
- เซ็ต "has_warning_sign": true, "urgency_level": "CRITICAL"
- SPOKEN FEEDBACK: "พบอาการหรือค่าความดันระดับวิกฤต! ให้นั่งพักนิ่งๆ ห้ามออกกำลังกายเด็ดขาด และกรุณาโทร 1669 หรือรีบไปโรงพยาบาลด่วนที่สุดค่ะ/ครับ"

### [4. รูปแบบการส่งออกข้อมูล (Output Format)]
ส่งผลลัพธ์กลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "answer": "ข้อความคำตอบภาษาไทยที่สุภาพ กระชับ",
  "has_warning_sign": true/false,
  "urgency_level": "NORMAL" | "ELEVATED" | "CRITICAL",
  "action_recommendation": "คำแนะนำสั้นๆ"
}
''';

  /// 🔄 ฟังก์ชันจัดการการเชื่อมต่อ API พร้อม Auto-Retry แบบ Exponential Backoff
  Future<GenerateContentResponse> _generateWithRetry({
    required List<Content> content,
    int maxRetries = 3,
  }) async {
    int attempts = 0;
    int delaySeconds = 2; // เริ่มหน่วงเวลาที่ 2 วินาที

    while (true) {
      attempts++;
      try {
        // พยายามเรียก API ด้วยโมเดลหลัก
        return await _primaryModel.generateContent(content);
      } catch (e) {
        final errorStr = e.toString();
        // ตรวจจับ Error ที่เกิดจากฝั่งเซิร์ฟเวอร์หนาแน่น
        final isServerBusy = errorStr.contains('503') ||
            errorStr.contains('high demand') ||
            errorStr.contains('UNAVAILABLE');

        if (isServerBusy && attempts <= maxRetries) {
          debugPrint(
              '⚠️ Gemini Server Busy (Attempt $attempts/$maxRetries). Retrying in $delaySeconds seconds...');
          await Future.delayed(Duration(seconds: delaySeconds));
          delaySeconds *= 2; // เพิ่มเวลาหน่วงตัวคูณสอง (2 -> 4 -> 8 วินาที)

          // หากลองรอบที่ 2 แล้วยังไม่สำเร็จ ให้สลับใช้ Fallback Model สำรอง
          if (attempts == 2) {
            debugPrint('🔄 Switching to Fallback Model (8B)...');
            try {
              return await _fallbackModel.generateContent(content);
            } catch (_) {
              // ถ้า Fallback พังอีก ให้วนลูปต่อจนครบโควต้า
            }
          }
        } else {
          // หากหมดโควต้า Retry หรือเป็น Error รูปแบบอื่น โยน Error กลับออกไป
          rethrow;
        }
      }
    }
  }

  /// 💬 สั่ง AI ตอบคำปรึกษาผู้ป่วย
  Future<Map<String, dynamic>> askConsult({
    required String userQuery,
    required Map<String, dynamic>? profileData,
  }) async {
    try {
      final String profileContext = profileData != null
          ? 'ข้อมูลผู้ป่วย: อายุ ${profileData['age'] ?? '-'} ปี, เพศ ${profileData['gender'] ?? 'ชาย'}, โรคประจำตัว: ${profileData['underlying_diseases'] ?? 'ไม่มี'}, น้ำหนัก ${profileData['weight_kg'] ?? '-'} kg, ส่วนสูง ${profileData['height_cm'] ?? '-'} cm'
          : 'ข้อมูลผู้ป่วย: ทั่วไป';

      final prompt = '''
$profileContext
คำถามปรึกษาจากผู้ป่วย: "$userQuery"
''';

      // เรียกใช้งานฟังก์ชันที่หุ้มด้วยระบบ Retry
      final response = await _generateWithRetry(
        content: [Content.text(prompt)],
      );

      if (response.text != null) {
        return jsonDecode(response.text!) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('❌ HtConsultService Error: $e');
    }

    // Fallback JSON ส่งกลับไปหน้า UI เมื่อระบบล่มจริงๆ (ไม่ต้องแครชแอป)
    return {
      "answer":
          "ขออภัยค่ะ ขณะนี้ระบบประมวลผลของ AI มีผู้ใช้งานหนาแน่นชั่วคราว หากมีอาการผิดปกติกรุณาติดต่อบุคลากรทางการแพทย์นะคะ",
      "has_warning_sign": false,
      "urgency_level": "NORMAL",
      "action_recommendation": "กรุณากดลองใหม่อีกครั้งในอีกสักครู่"
    };
  }
}
