import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'patient_profile_service.dart';

class VoiceHealthService {
  final String apiKey;
  late final GenerativeModel _model;
  final PatientProfileService _profileService = PatientProfileService();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsReady = false;

  static final Schema _healthDataSchema = Schema.object(
    properties: {
      'is_valid_health_data': Schema.boolean(
        description: 'เป็น true หากเป็นข้อมูลสุขภาพหรืออาการจริง',
      ),
      'patient_category': Schema.string(
        description:
            'จำแนกกลุ่มผู้ป่วย: NEW_CASE_OR_GENERAL, HT_ONLY, DLP_ONLY, HT_WITH_DLP, HT_WITH_DM, HT_WITH_CKD, HT_DM_DLP_COMBINED, PREVIOUS_CVD_OR_STROKE',
      ),
      'systolic': Schema.integer(
        nullable: true,
        description: 'ความดันตัวบน ถ้าไม่ได้พูดถึงให้ใส่ null',
      ),
      'diastolic': Schema.integer(
        nullable: true,
        description: 'ความดันตัวล่าง ถ้าไม่ได้พูดถึงให้ใส่ null',
      ),
      'pulse': Schema.integer(
        nullable: true,
        description: 'ชีพจร ถ้าไม่ได้พูดถึงให้ใส่ null',
      ),
      'fasting_blood_sugar': Schema.number(
        nullable: true,
        description: 'ค่าน้ำตาลในเลือด ถ้าไม่ได้พูดถึงให้ใส่ null',
      ),
      'waist_cm': Schema.number(
        nullable: true,
        description: 'รอบเอว (เซนติเมตร) ถ้าไม่ได้พูดถึงให้ใส่ null',
      ),
      'urgency_level': Schema.string(
        description: 'ประเมินระดับความรุนแรง: NORMAL, WARNING, CRISIS',
      ),
      'has_warning_sign': Schema.boolean(
        description: 'เป็น true หากมีสัญญาณอันตราย 1669',
      ),
      'warning_details': Schema.string(
        nullable: true,
        description: 'รายละเอียดสัญญาณอันตราย',
      ),
      'spoken_feedback': Schema.string(
        description: 'คำตอบรับสั้นๆ ภาษาไทยสำหรับอ่านให้ผู้ป่วยฟัง',
      ),
      'is_missing_data': Schema.boolean(
        description: 'เป็น true หากผู้ป่วยแจ้งความดันไม่ครบ',
      ),
    },
    requiredProperties: [
      'is_valid_health_data',
      'patient_category',
      'urgency_level',
      'has_warning_sign',
      'spoken_feedback',
      'is_missing_data',
    ],
  );

  VoiceHealthService(this.apiKey) {
    _model = GenerativeModel(
      model: 'gemini-3.6-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _healthDataSchema,
      ),
    );
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("th-TH");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isTtsReady = true;
      debugPrint('🔊 FlutterTTS initialized successfully');
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  Future<void> speakFeedback(String text) async {
    if (!_isTtsReady || text.isEmpty) return;
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Error in speakFeedback: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
  }

  // 📍 1. ฟังก์ชันสกัดข้อมูลสุขภาพจากการพูด (STT)
  // 📍 1. ฟังก์ชันสกัดข้อมูลสุขภาพจากการพูด (STT)
  Future<Map<String, dynamic>?> processSpeechToHealthData(
      String speechText) async {
    try {
      final profileContext = await _profileService.getProfilePromptContext();
      final prompt = '''
ประมวลผลข้อความพูดของผู้ป่วย: "$speechText"
บริบทโปรไฟล์ผู้ป่วยปัจจุบัน: $profileContext
ถอดค่าสุขภาพและประเมินระดับความรุนแรงทางการแพทย์ให้ถูกต้อง
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      String? text = response.text;

      if (text != null && text.isNotEmpty) {
        // 🛠️ [Fix]: ทำความสะอาด Markdown String ก่อน parse JSON
        text = text.trim();
        if (text.startsWith('```json')) text = text.substring(7);
        if (text.startsWith('```')) text = text.substring(3);
        if (text.endsWith('```')) text = text.substring(0, text.length - 3);
        text = text.trim();

        return jsonDecode(text) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error processing speech data: $e');
      return null;
    }
  }

  // 📍 2. ฟังก์ชันอ่านหน้าจอเครื่องวัดความดัน (LCD Image OCR)
  // 📍 2. ฟังก์ชันอ่านหน้าจอเครื่องวัดความดัน (LCD Image OCR)
  Future<Map<String, dynamic>?> processLcdImageInput(File imageFile) async {
    try {
      // 🛠️ [Fix]: บังคับ GenerationConfig เป็น JSON และดึง _healthDataSchema มาใช้
      final ocrModel = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _healthDataSchema,
        ),
      );

      final imageBytes = await imageFile.readAsBytes();
      final content = [
        Content.multi([
          TextPart(
              'อ่านค่าความดันตัวบน (systolic), ตัวล่าง (diastolic), และชีพจร (pulse) จากรูปภาพหน้าจอเครื่องวัดความดัน หากอ่านค่าใดไม่ได้ให้ใส่ null ในฟิลด์นั้นๆ'),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await ocrModel.generateContent(content);
      String? text = response.text;

      if (text != null && text.isNotEmpty) {
        // 🛠️ [Fix]: ทำความสะอาด Markdown String เผื่อกรณี AI ตอบกลับติด Format
        text = text.trim();
        if (text.startsWith('```json')) text = text.substring(7);
        if (text.startsWith('```')) text = text.substring(3);
        if (text.endsWith('```')) text = text.substring(0, text.length - 3);
        text = text.trim();

        return jsonDecode(text) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error processing LCD Image: $e');
      return null;
    }
  }

  // 📍 3. ฟังก์ชันสกัดข้อมูลใบแล็บ (Lab Report OCR)
  Future<Map<String, dynamic>?> processLabReportImage(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final visionModel =
          GenerativeModel(model: 'gemini-3.6-flash', apiKey: apiKey);
      final content = [
        Content.multi([
          TextPart(
              'วิเคราะห์ใบแล็บและสกัดค่า Total Cholesterol, HDL, LDL, Fasting Blood Sugar, Creatinine ออกมาเป็น JSON'),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await visionModel.generateContent(content);
      final text = response.text;
      if (text != null) {
        String cleanedJson = text.trim();
        if (cleanedJson.startsWith('```json'))
          cleanedJson = cleanedJson.substring(7);
        if (cleanedJson.endsWith('```'))
          cleanedJson = cleanedJson.substring(0, cleanedJson.length - 3);
        return jsonDecode(cleanedJson.trim()) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Lab Report OCR Error: $e');
      return null;
    }
  }

  // 📍 4. ฟังก์ชันสกัดข้อมูลยาจากรูปถ่ายฉลากยาด้วย Gemini Vision OCR
  Future<Map<String, dynamic>?> processDrugLabelImage(File imageFile) async {
    try {
      final visionModel = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: apiKey,
        // 🚀 บังคับให้ Gemini คืนค่าเป็น JSON เท่านั้น (หมดปัญหา AI พิมพ์อธิบายแทรก)
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final imageBytes = await imageFile.readAsBytes();

      // 🚀 ตรวจสอบนามสกุลไฟล์อัตโนมัติ (รองรับทั้ง iOS และ Android)
      final extension = imageFile.path.split('.').last.toLowerCase();
      final mimeType = (extension == 'png') ? 'image/png' : 'image/jpeg';

      final content = [
        Content.multi([
          TextPart(
              'จงวิเคราะห์และสกัดข้อมูลฉลากยาจากภาพนี้ และตอบกลับเป็น JSON รูปแบบนี้เท่านั้น:\n'
              '{\n'
              '  "medication_name": "ชื่อยา (ถ้าเป็นภาษาอังกฤษให้คงไว้)",\n'
              '  "dosage_instruction": "วิธีใช้ยา (เช่น รับประทานครั้งละ 1 เม็ด หลังอาหารเช้า เย็น)",\n'
              '  "is_morning_active": true หรือ false,\n'
              '  "time_morning": "08:00",\n'
              '  "is_noon_active": true หรือ false,\n'
              '  "time_noon": "12:00",\n'
              '  "is_evening_active": true หรือ false,\n'
              '  "time_evening": "18:00"\n'
              '}\n'
              'หากมื้อไหนไม่มีระบุในฉลาก ให้ตั้งค่า is_..._active เป็น false และเวลาเป็น "08:00"'),
          DataPart(mimeType, imageBytes),
        ])
      ];

      final response = await visionModel.generateContent(content);
      final text = response.text;

      if (text != null && text.isNotEmpty) {
        // เนื่องจากล็อก responseMimeType แล้ว ข้อมูลที่ได้จะเป็น JSON ล้วนๆ ทันที
        return jsonDecode(text.trim());
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error processDrugLabelImage (Gemini OCR): $e');
      return null;
    }
  }
}
