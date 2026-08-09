import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/patient_profile_service.dart';
import 'home_screen.dart';
import '../services/patient_database_service.dart';

enum OnboardingStep { age, weightHeight, diseases, medication, lifestyle, confirmation }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();

  OnboardingStep _currentStep = OnboardingStep.age;
  bool _isListening = false;
  String _spokenText = "";
  bool _isSaving = false;

  // ค่าตัวแปรที่จะใช้เก็บข้อมูลจริง
  int _age = 45;
  double _weight = 76.0;
  double _height = 170.0;
  String _diseases = 'ยังไม่ระบุ';
  bool _takesMedication = false;
  bool _smokes = false;
  bool _drinksAlcohol = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _speakCurrentQuestion();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
  }

  Future<void> _speakCurrentQuestion() async {
    String text = "";
    switch (_currentStep) {
      case OnboardingStep.age:
        text = "สวัสดีค่ะ คุณอายุเท่าไหร่คะ?";
        break;
      case OnboardingStep.weightHeight:
        text = "น้ำหนัก และส่วนสูงของคุณ เท่าไหร่คะ?";
        break;
      case OnboardingStep.diseases:
        text = "คุณมีโรคประจำตัวอะไรบ้างคะ เช่น เบาหวาน ความดัน หรือไม่มีคะ?";
        break;
      case OnboardingStep.medication:
        text = "ปัจจุบันคุณทานยาประจำอยู่หรือไม่คะ?";
        break;
      case OnboardingStep.lifestyle:
        text = "คุณสูบบุหรี่ หรือดื่มเครื่องดื่มแอลกอฮอล์บ้างไหมคะ?";
        break;
      case OnboardingStep.confirmation:
        text = "กรุณาตรวจสอบข้อมูลสุขภาพของคุณให้ถูกต้องก่อนบันทึกค่ะ";
        break;
    }
    await _flutterTts.setLanguage("th-TH");
    await _flutterTts.speak(text);
  }

  void _startListening() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(onResult: (result) {
          setState(() {
            _spokenText = result.recognizedWords;
          });
          if (result.finalResult) {
            _processAnswer(_spokenText);
          }
        });
      }
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  void _processAnswer(String text) {
    _stopListening();
    setState(() {
      switch (_currentStep) {
        case OnboardingStep.age:
          _age = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 45;
          _currentStep = OnboardingStep.weightHeight;
          break;
        case OnboardingStep.weightHeight:
          // ดึงตัวเลขจากคำพูด เช่น "หนัก 76 สูง 170"
          final numbers = RegExp(r'\d+').allMatches(text).map((m) => double.parse(m.group(0)!)).toList();
          if (numbers.length >= 2) {
            _weight = numbers[0];
            _height = numbers[1];
          } else if (numbers.length == 1) {
            _weight = numbers[0];
          }
          _currentStep = OnboardingStep.diseases;
          break;
        case OnboardingStep.diseases:
          _diseases = text;
          _currentStep = OnboardingStep.medication;
          break;
        case OnboardingStep.medication:
          _takesMedication = text.contains("ทาน") || text.contains("มี") || text.contains("กิน");
          _currentStep = OnboardingStep.lifestyle;
          break;
        case OnboardingStep.lifestyle:
          _smokes = text.contains("สูบ");
          _drinksAlcohol = text.contains("ดื่ม");
          _currentStep = OnboardingStep.confirmation; // วิ่งเข้าหน้าตรวจสอบข้อมูล
          break;
        case OnboardingStep.confirmation:
          break;
      }
    });
    
    // ถ้าถึงหน้า confirmation ไม่ต้องพูดคำถามเสียงแล้ว ให้เปิด Popup ทันที
    if (_currentStep == OnboardingStep.confirmation) {
      _showConfirmationDialog();
    } else {
      _speakCurrentQuestion();
    }
  }

  // 📍 Popup ตรวจสอบข้อมูลก่อนบันทึกจริงลง Supabase
  void _showConfirmationDialog() {
    final ageController = TextEditingController(text: _age.toString());
    final weightController = TextEditingController(text: _weight.toString());
    final heightController = TextEditingController(text: _height.toString());
    final diseaseController = TextEditingController(text: _diseases);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('ตรวจสอบข้อมูลสุขภาพ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('คุณสามารถแก้ไขข้อมูลให้ถูกต้องก่อนบันทึกลงระบบได้ครับ', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'อายุ (ปี)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'น้ำหนัก (กก.)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ส่วนสูง (ซม.)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diseaseController,
                decoration: const InputDecoration(labelText: 'โรคประจำตัว', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _currentStep = OnboardingStep.age); // ย้อนกลับไปเริ่มใหม่ถ้าต้องการ
            },
            child: const Text('เริ่มพูดใหม่', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              // ดึงค่าที่อาจจะถูกแก้ใน Popup มาอัปเดตใส่ตัวแปร
              setState(() {
                _age = int.tryParse(ageController.text) ?? _age;
                _weight = double.tryParse(weightController.text) ?? _weight;
                _height = double.tryParse(heightController.text) ?? _height;
                _diseases = diseaseController.text;
              });

              Navigator.pop(ctx); // ปิด Popup
              await _saveAndPushToSupabase(); // บันทึกลง Supabase ทันที
            },
            child: const Text('ยืนยันและบันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 📍 ฟังก์ชันบันทึกข้อมูลตัวจริงลง Supabase และ SharedPreferences
  Future<void> _saveAndPushToSupabase() async {
    setState(() => _isSaving = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      
      if (patientId != null) {
        // คำนวณ BMI อัตโนมัติจากน้ำหนักและส่วนสูงใหม่
        double heightM = _height / 100.0;
        double calculatedBmi = (heightM > 0) ? (_weight / (heightM * heightM)) : 0.0;

        // 1. บันทึกตรงขึ้น Supabase Cloud (ตาราง patients)
        await _dbService.updatePatientOnboardingData(
          patientId: patientId,
          weight: _weight,
          height: _height,
          bmi: double.parse(calculatedBmi.toStringAsFixed(1)),
          underlyingDiseases: _diseases,
          lifestyleNotes: 'สูบบุหรี่: $_smokes, ดื่มสุรา: $_drinksAlcohol',
        );
        debugPrint('✅ บันทึกข้อมูล Onboarding ลง Supabase สำเร็จเรียบร้อย!');
      }

      // 2. อัปเดตข้อมูลลง Local Storage
      await _profileService.updateLocalProfile({
        'age': _age,
        'weight_kg': _weight,
        'height_cm': _height,
        'underlying_diseases': _diseases,
        'takes_medication': _takesMedication,
      });

      if (mounted) {
        // 3. พาเข้าสู่หน้า Home Dashboard หลัก
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving onboarding data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('เก็บข้อมูลสุขภาพเบื้องต้น'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF10B981)),
                  SizedBox(height: 16),
                  Text('กำลังบันทึกข้อมูลลงฐานข้อมูล...', style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      'ขั้นตอนที่ ${_currentStep.index + 1} / 6',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.support_agent_rounded, size: 64, color: Color(0xFF10B981)),
                          const SizedBox(height: 16),
                          Text(
                            _spokenText.isEmpty ? "กำลังรอคำตอบ..." : '\"$_spokenText\"',
                            style: const TextStyle(fontSize: 20, color: Color(0xFF334155)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _isListening ? _stopListening : _startListening,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: _isListening ? Colors.red : const Color(0xFF10B981),
                        child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
                      ),
                    ),
                    Text(
                      _isListening ? 'กำลังฟัง...' : 'แตะเพื่อพูด',
                      style: TextStyle(
                        fontSize: 18, 
                        color: _isListening ? Colors.red : const Color(0xFF10B981), 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    if (_currentStep != OnboardingStep.confirmation)
                       TextButton(
                          onPressed: () {
                            setState(() {
                               _currentStep = OnboardingStep.confirmation;
                            });
                            _showConfirmationDialog();
                          }, 
                          child: const Text("ข้ามไปตรวจสอบข้อมูล (Skip)")
                       )
                  ],
                ),
              ),
            ),
    );
  }
}