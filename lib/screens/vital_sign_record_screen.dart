import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../config/app_config.dart';
import '../services/voice_health_service.dart';
import '../widgets/modern_voice_button.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../widgets/image_input_field.dart';
import '../widgets/save_confirmation_dialog.dart';

class VitalSignRecordScreen extends StatefulWidget {
  const VitalSignRecordScreen({super.key});

  @override
  State<VitalSignRecordScreen> createState() => _VitalSignRecordScreenState();
}

class _VitalSignRecordScreenState extends State<VitalSignRecordScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();

  late VoiceHealthService _voiceService;
  late stt.SpeechToText _speech;
  final FlutterTts _flutterTts = FlutterTts();

  bool _isListening = false;
  bool _isProcessing = false;
  bool _isPlayingAdvice = false;
  bool _hasPlayedIntro = false;
  String _lastWords = '';

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _voiceService = VoiceHealthService(AppConfig.geminiApiKey);

    // 📍 เล่นเสียงคำแนะนำหลัง UI วาดเสร็จเรียบร้อย ป้องกัน Race Condition
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initTtsAndPlayIntro();
    });
  }

  /// 📍 ตั้งค่า TTS และสั่งเล่นเสียงคำแนะนำเปิดหน้าทันที
  Future<void> _initTtsAndPlayIntro() async {
    try {
      await _flutterTts.setLanguage("th-TH");
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isPlayingAdvice = false);
      });

      _flutterTts.setCancelHandler(() {
        if (mounted) setState(() => _isPlayingAdvice = false);
      });

      _flutterTts.setErrorHandler((msg) {
        if (mounted) setState(() => _isPlayingAdvice = false);
      });

      if (!_hasPlayedIntro) {
        _hasPlayedIntro = true;
        _toggleAdviceVoice(); // สั่งเล่นเสียงคำแนะนำทันที
      }
    } catch (e) {
      debugPrint("❌ Init TTS Error: $e");
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  /// 📍 ฟังก์ชันกดเปิด / ปิด / เล่นซ้ำ เสียงคำแนะนำก่อนวัดความดัน
  Future<void> _toggleAdviceVoice() async {
    if (_isPlayingAdvice) {
      // หากกำลังเล่นอยู่ -> กดเพื่อปิดเสียง
      await _flutterTts.stop();
      if (mounted) setState(() => _isPlayingAdvice = false);
    } else {
      // หากปิดอยู่ -> กดเพื่อเล่นซ้ำ
      if (mounted) setState(() => _isPlayingAdvice = true);

      String patientName = "";
      try {
        final profile = await _profileService.getProfile();
        if (profile != null &&
            profile['first_name'] != null &&
            profile['first_name'].toString().isNotEmpty) {
          patientName = "คุณ ${profile['first_name']}";
        }
      } catch (_) {}

      String adviceText =
          "ยินดีต้อนรับ$patientName ให้นั่งพักผ่อนในที่เงียบๆ และสบายตัวอย่างน้อย 5 นาทีก่อนเริ่มวัดนะคะ "
          "ห้ามพูดคุยหรือเล่นโทรศัพท์มือถือในระหว่างที่กำลังนั่งพักและขณะทำการวัด "
          "งดสารกระตุ้น ห้ามสูบบุหรี่ หรือดื่มเครื่องดื่มที่มีชา กาแฟ และคาเฟอีนอย่างน้อย 30 นาทีก่อนวัด "
          "งดออกกำลังกายอย่างหนัก ทานอาหารมื้อใหญ่ หรือดื่มแอลกอฮอล์ก่อนวัด 30 นาที "
          "ควรเข้าห้องน้ำปัสสาวะให้เรียบร้อยก่อน เพราะกระเพาะปัสสาวะเต็มอาจทำให้ค่าความดันสูงขึ้น "
          "ท่านั่งที่ถูกต้อง นั่งหลังพิงพนักเก้าอี้อย่างสบาย วางเท้าพราบกับพื้นทั้งสองข้าง และไม่ไขว่ห้าง "
          "วางแขนบนโต๊ะโดยให้ระดับของแขนอยู่สูงเท่ากับตำแหน่งของหัวใจ "
          "ควรสวมปลอกแขนสัมผัสกับผิวหนังโดยตรง และพันให้เหนือข้อพับศอกขึ้นมาประมาณ 2-3 เซนติเมตรค่ะ "
          "หากวัดที่สถานพยาบาลควรวัดอย่างน้อย 3 ครั้ง แล้วนำค่า 2 ครั้งหลังมาหาค่าเฉลี่ยนะคะ";

      // 📍 บังคับ Reset State การเล่น
      var result = await _flutterTts.speak(adviceText);
      if (result != 1 && mounted) {
        setState(() => _isPlayingAdvice = false);
      }
    }
  }

  void _startListening() async {
    if (_isPlayingAdvice) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isPlayingAdvice = false);
    }

    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _lastWords = '';
      });
      _speech.listen(onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
        if (result.finalResult) {
          _processVoice(_lastWords);
        }
      });
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _showHypotensionAlert(
      {required String patientId,
      required int sys,
      required int dia,
      required String spokenFeedback,
      required Map<String, dynamic> healthData}) async {
    try {
      await _dbService.saveAlertComplication(
          patientId: patientId,
          alertType: 'HYPOTENSION',
          severity: 'HIGH',
          symptomsReported: 'ความดันโลหิตต่ำ ($sys/$dia mmHg)');
    } catch (e) {
      debugPrint('Error saving hypotension alert: $e');
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.orange.shade50,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
              SizedBox(width: 8),
              Expanded(
                  child: Text('ระวังภาวะความดันต่ำ!',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)))
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ค่าวัดความดัน: $sys/$dia mmHg',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange)),
              const SizedBox(height: 10),
              const Text('ค่าวัดนี้ต่ำกว่าเกณฑ์ปกติ (90/60 mmHg)',
                  style: TextStyle(fontSize: 15, color: Colors.black87)),
              const SizedBox(height: 14),
              const Text(
                  '⚠️ หากมีอาการหน้ามืด วูบ หรือใจสั่น ให้นอนราบยกขาขึ้นสูง เปลี่ยนอิริยาบถช้าๆ และรีบแจ้งญาติหรือพบแพทย์ทันที',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ยกเลิก / วัดใหม่',
                    style: TextStyle(color: Colors.grey, fontSize: 16))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(ctx);
                healthData['urgency_level'] = 'HYPOTENSION';
                _showSaveConfirmation(healthData);
              },
              child: const Text('ยืนยันค่านี้ถูกต้อง',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleEmergencyAlert(
      {required String patientId,
      required int sys,
      required int dia,
      required String spokenFeedback,
      List<dynamic>? symptoms}) async {
    try {
      await _dbService.saveAlertComplication(
          patientId: patientId,
          alertType: 'HYPERTENSIVE_CRISIS',
          severity: 'CRISIS',
          symptomsReported: symptoms != null && symptoms.isNotEmpty
              ? symptoms.join(', ')
              : 'ความดันสูงระดับวิกฤต ($sys/$dia mmHg)');
      await _dbService.saveVitalSigns(
          patientId: patientId,
          systolic: sys,
          diastolic: dia,
          pulse: null,
          spokenFeedback: spokenFeedback,
          urgencyLevel: 'CRISIS',
          imageUrl: null);
    } catch (e) {
      debugPrint('Error saving emergency data: $e');
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.red.shade50,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
              SizedBox(width: 8),
              Expanded(
                  child: Text('เตือนภัยระดับวิกฤต!',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)))
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ค่าวัดความดัน: $sys/$dia mmHg',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent)),
              const SizedBox(height: 10),
              Text(spokenFeedback,
                  style: const TextStyle(fontSize: 15, color: Colors.black87)),
              const SizedBox(height: 14),
              const Text(
                  '⚠️ หากมีอาการแน่นหน้าอก ปากเบี้ยว แขนขาอ่อนแรง หรือปวดศีรษะรุนแรง ให้รีบกดโทร 1669 เพื่อขอความช่วยเหลือด่วน',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('รับทราบ',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.phone_in_talk, color: Colors.white),
              label: const Text('โทร 1669 ด่วน',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final Uri launchUri = Uri(scheme: 'tel', path: '1669');
                if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
              },
            ),
          ],
        ),
      );
    }
  }

  Future<void> _validateAndRouteData(Map<String, dynamic> healthData) async {
    final sys = healthData['systolic'];
    final dia = healthData['diastolic'];
    final urgency = healthData['urgency_level'];
    final feedback = healthData['spoken_feedback']; //**** */
    final symptoms = healthData['symptoms'];

    final sysInt =
        (sys is int) ? sys : int.tryParse(sys?.toString() ?? '') ?? 0;
    final diaInt =
        (dia is int) ? dia : int.tryParse(dia?.toString() ?? '') ?? 0;

    bool isValidBP = (sysInt > diaInt) &&
        (sysInt >= 50 && sysInt <= 300) &&
        (diaInt >= 30 && diaInt <= 200);

    if (!isValidBP) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.error_outline, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('ข้อมูลไม่สมเหตุสมผล')
            ]),
            content: Text(
                'ค่าความดัน $sysInt/$diaInt mmHg ที่รับเข้ามาไม่ถูกต้องตามหลักการแพทย์ กรุณาวัดหรือระบุค่าใหม่อีกครั้งค่ะ'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ตกลง'))
            ],
          ),
        );
      }
      return;
    }

    final patientId = await _profileService.getCurrentPatientId() ?? '';

    // ด่านที่ 1: จำกัดสิทธิ์โควต้าต่อวัน (Max 3/Day)
    bool canSave = await _dbService.canSaveVitalSignToday(patientId);
    if (!canSave) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.pan_tool_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('บันทึกครบโควต้าแล้ว')
            ]),
            content: const Text(
                'คุณบันทึกค่าความดันครบ 3 ครั้งในวันนี้แล้ว ตามมาตรฐานทางการแพทย์ไม่ควรวัดความดันพร่ำเพรื่อเพื่อลดความวิตกกังวลค่ะ'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ตกลง'))
            ],
          ),
        );
      }
      return;
    }
// 📍 [แก้บั๊กที่ 2]: ย้ายคำสั่งเสียงมาไว้ตรงนี้!
    // ทันทีที่ข้อมูลถูกตรวจสอบว่าไม่เกินโควต้า ให้ AI พูดคำแนะนำทันที
    // ไม่ว่าหลังจากนี้จะเป็นความดันปกติ หรือวิกฤต AI ก็จะได้พูดเสมอ
    if (feedback != null && feedback.toString().isNotEmpty) {
      _voiceService.speakFeedback(feedback.toString());
    }

    // ด่านที่ 2: บังคับพัก 3 นาที
    if (sysInt >= 135 || diaInt >= 85) {
      DateTime? lastTime =
          await _dbService.getLastMeasurementTimeToday(patientId);

      if (lastTime != null) {
        final nowLocal = DateTime.now();
        final diffMinutes = nowLocal.difference(lastTime).inMinutes;

        if (diffMinutes < 3) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [
                  Icon(Icons.timer_rounded, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('กรุณาพักก่อนวัดใหม่')
                ]),
                content: const Text(
                    'การวัดซ้ำควรเว้นระยะห่างอย่างน้อย 3 นาที กรุณานั่งพักผ่อนให้สบายใจ แล้วค่อยทำการวัดใหม่อีกครั้งนะคะ'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ตกลง'))
                ],
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.blue.shade50,
              title: const Row(children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 30),
                SizedBox(width: 8),
                Text('ข้อแนะนำการวัดซ้ำ', style: TextStyle(color: Colors.blue))
              ]),
              content: const Text(
                  'พบว่าค่าความดันครั้งแรกของคุณค่อนข้างสูง กรุณานั่งพักผ่อนทำใจให้สบาย 3 นาที แล้วจึงทำการวัดครั้งที่ 2 เพื่อยืนยันผลนะคะ (ระบบกำลังบันทึกค่าแรกนี้ไว้เป็นสถิติ)'),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSaveConfirmation(healthData);
                  },
                  child: const Text('รับทราบ'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    // ด่านที่ 3: ดักความดันตก/ความดันวิกฤต
    if (sysInt < 90 || diaInt < 60) {
      await _showHypotensionAlert(
          patientId: patientId,
          sys: sysInt,
          dia: diaInt,
          spokenFeedback: feedback?.toString() ?? 'ความดันโลหิตต่ำกว่าปกติ',
          healthData: healthData);
      return;
    }

    if (urgency == 'CRISIS' || sysInt >= 180 || diaInt >= 110) {
      await _handleEmergencyAlert(
          patientId: patientId,
          sys: sysInt,
          dia: diaInt,
          spokenFeedback: feedback?.toString() ?? 'ความดันโลหิตสูงระดับวิกฤต',
          symptoms: symptoms is List ? symptoms : null);
      return;
    }

    _showSaveConfirmation(healthData);
  }

  Future<void> _processVoice(String text) async {
    // 📍 [แก้บั๊กที่ 1]: สั่งปิดไมค์และคืน Audio Focus ให้ระบบทันที
    // เพื่อให้ลำโพง (TTS) ว่างและพร้อมสำหรับการเล่นเสียง AI
    await _speech.stop();
    setState(() {
      _isListening = false;
      _isProcessing = true;
    });

    try {
      final healthData = await _voiceService.processSpeechToHealthData(text);
      if (healthData != null) {
        if (mounted) await _validateAndRouteData(healthData);
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _imageFile = imageFile;
      _isProcessing = true;
    });

    try {
      final healthData = await _voiceService.processLcdImageInput(imageFile);
      if (healthData != null && healthData['is_valid_health_data'] == true) {
        if (mounted) await _validateAndRouteData(healthData);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'ไม่สามารถอ่านค่าความดันจากรูปภาพได้ กรุณาถ่ายใหม่อีกครั้ง')));
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการอ่านรูปภาพ: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSaveConfirmation(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => SaveConfirmationDialog(
        healthData: data,
        imageFile: _imageFile,
        onConfirm: (updatedData) => _saveDataToDb(updatedData),
      ),
    );
  }

  Future<void> _saveDataToDb(Map<String, dynamic> data) async {
    print('🚨 ข้อมูลที่ส่งมาถึงฟังก์ชันเซฟ: $data'); // <--- เติมบรรทัดนี้
    setState(() => _isProcessing = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        throw Exception('ไม่พบรหัสผู้ป่วย กรุณาเข้าสู่ระบบใหม่');
      }

      String? uploadedUrl;
      if (_imageFile != null) {
        uploadedUrl =
            await _dbService.uploadHealthImage(_imageFile!, patientId);
      }

      await _dbService.saveVitalSigns(
        patientId: patientId,
        systolic: data['systolic'] ?? 0,
        diastolic: data['diastolic'] ?? 0,
        pulse: data['pulse'],
        spokenFeedback: data['spoken_feedback'],
        urgencyLevel: data['urgency_level'],
        imageUrl: uploadedUrl,
      );

      double? weight = data['weight_kg'] ??
          double.tryParse(data['weight']?.toString() ?? '');
      double? height = data['height_cm'] ??
          double.tryParse(data['height']?.toString() ?? '');
      String? disease = data['underlying_diseases']?.toString();

      double? bmi;
      if (weight != null && height != null && weight > 0 && height > 0) {
        double heightInMeters = height / 100;
        bmi = weight / (heightInMeters * heightInMeters);
        bmi = double.parse(bmi.toStringAsFixed(2));
      }

      final updateData = <String, dynamic>{};
      if (weight != null && weight > 0) updateData['weight_kg'] = weight;
      if (height != null && height > 0) updateData['height_cm'] = height;
      if (bmi != null && bmi > 0) updateData['bmi'] = bmi;
      if (disease != null && disease.isNotEmpty)
        updateData['underlying_diseases'] = disease;

      if (updateData.isNotEmpty) {
        await Supabase.instance.client
            .from('patients')
            .update(updateData)
            .eq('id', patientId);
        await _profileService.updateLocalProfile(updateData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('บันทึกข้อมูลและอัปเดตโปรไฟล์สำเร็จ'),
              backgroundColor: emeraldColor),
        );
        setState(() {
          _imageFile = null;
          _lastWords = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: slateColor),
          onPressed: () {
            _flutterTts.stop();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'บันทึกความดันโลหิต',
          style: TextStyle(
              color: slateColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 📍 ปุ่มแถบสีแดงสำหรับกด ปิด / เล่นซ้ำ เสียงคำแนะนำ
            GestureDetector(
              onTap: _toggleAdviceVoice,
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isPlayingAdvice
                      ? Colors.orange.shade700
                      : Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                        _isPlayingAdvice
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isPlayingAdvice
                            ? 'กำลังเล่นคำแนะนำ... (แตะเพื่อหยุด)'
                            : 'คำแนะนำก่อนวัดความดัน (แตะเพื่อฟัง)',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildVoiceStatusCard(),
            const SizedBox(height: 30),
            ModernVoiceButton(
              isListening: _isListening,
              isProcessing: _isProcessing,
              onTap: _isListening ? _stopListening : _startListening,
            ),
            const SizedBox(height: 40),
            ImageInputField(
              onImageSelected: (file) {
                _processImage(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          const Text('พูดค่าความดันและชีพจรของคุณ',
              style: TextStyle(
                  color: slateColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            _lastWords.isEmpty
                ? '"ความดัน 120 ตัวล่าง 80 ชีพจร 75"'
                : 'กำลังประมวลผล: "$_lastWords"',
            style: TextStyle(
                color: _lastWords.isEmpty ? Colors.grey : emeraldColor,
                fontSize: _lastWords.isEmpty ? 14 : 16,
                fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
