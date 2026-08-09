import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/vital_repository.dart';
import '../services/th_cv_risk_calculator.dart'; // โมเดลคำนวณความเสี่ยงเดิม

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = PatientProfileService();
  final _dbService = PatientDatabaseService();
  final _vitalRepository = VitalRepository();

  final _fNameController = TextEditingController();
  final _lNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _bmiController = TextEditingController(); 
  final _diseaseController = TextEditingController();

  bool _isSmoker = false; // 📍 สถานะสูบบุหรี่ (แก้ไขได้)
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _latestLab;
  int _latestSystolic = 120; // 📍 ค่าความดันตัวบนล่าสุดจากประวัติจริง

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _loadProfileFast();
  }

  /// 🚀 โหลดโปรไฟล์ด่วนจากเครื่อง (ไม่ให้หน้าจอดำ) แล้วดึงแล็บ/ความดันเบื้องหลัง
  Future<void> _loadProfileFast() async {
    try {
      final profile = await _profileService.getProfile();
      if (profile != null) {
        setState(() {
          _profileData = profile;
          _fNameController.text = profile['first_name'] ?? '';
          _lNameController.text = profile['last_name'] ?? '';
          _ageController.text = (profile['age'] ?? '').toString();
          _weightController.text = (profile['weight'] ?? profile['weight_kg'] ?? '').toString();
          _heightController.text = (profile['height'] ?? profile['height_cm'] ?? '').toString();
          _bmiController.text = (profile['bmi'] ?? '').toString();
          _diseaseController.text = profile['underlying_diseases'] ?? profile['diseases'] ?? '';
          _isSmoker = profile['smokes'] == true || profile['smokers'] == true;
          _isLoading = false; // ปลดล็อกหน้าจอให้แสดงผลทันที
        });

        if (profile['id'] != null) {
          _loadBackgroundData(profile['id'].toString());
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading profile fast: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 🔄 ดึงผลแล็บและความดันล่าสุดแบบ Background (ไม่บล็อก UI)
  Future<void> _loadBackgroundData(String patientId) async {
    try {
      final labs = await _dbService.getLabResults(patientId);
      final vitals = await _vitalRepository.getLast7Days(patientId);

      if (mounted) {
        setState(() {
          if (labs.isNotEmpty) _latestLab = labs.first;
          if (vitals.isNotEmpty) {
            _latestSystolic = (vitals.first['systolic'] as num?)?.toInt() ?? 120;
          }
        });
      }
    } catch (e) {
      debugPrint('Background data fetch error: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; });

    final updateData = {
      'age': int.tryParse(_ageController.text) ?? 0,
      'weight': double.tryParse(_weightController.text) ?? 0.0,
      'height': double.tryParse(_heightController.text) ?? 0.0,
      'underlying_diseases': _diseaseController.text,
      'smokes': _isSmoker, // บันทึกสถานะสูบบุหรี่
    };

    // บันทึกลงเครื่อง (Local)
    await _profileService.updateLocalProfile(updateData);

    // บันทึกลง Supabase (Cloud)
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null && patientId.isNotEmpty) {
        await Supabase.instance.client.from('patients').update({
          'age': updateData['age'],
          'weight_kg': updateData['weight'],
          'height_cm': updateData['height'],
          'underlying_diseases': updateData['underlying_diseases'],
          'smokes': updateData['smokes'],
        }).eq('id', patientId);
      }
    } catch (e) {
      debugPrint('Error syncing profile to Supabase: $e');
    }

    if (mounted) {
      setState(() { 
        _isSaving = false;
        _profileData?.addAll(updateData);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('บันทึกข้อมูลโปรไฟล์และสถานะเรียบร้อยแล้ว'),
          backgroundColor: emeraldColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fNameController.dispose();
    _lNameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _bmiController.dispose();
    _diseaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('โปรไฟล์ผู้ป่วยและการประเมินความเสี่ยง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: emeraldColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🌟 1. การ์ดประเมิน Thai CVD Risk พรีเมียม (ดึงค่าความดันจริง & สถานะสูบบุหรี่จริง)
                    _buildThaiCvdRiskCard(),
                    const SizedBox(height: 24),

                    // 📝 2. ฟอร์มข้อมูลส่วนตัวและสุขภาพ
                    const Text('ข้อมูลส่วนตัวและสุขภาพ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: slateColor)),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _fNameController, decoration: _inputDecoration('ชื่อ', Icons.person_outline))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: _lNameController, decoration: _inputDecoration('นามสกุล', Icons.person))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _ageController, keyboardType: TextInputType.number, decoration: _inputDecoration('อายุ (ปี)', Icons.cake_outlined))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: _weightController, keyboardType: TextInputType.number, decoration: _inputDecoration('น้ำหนัก (กก.)', Icons.monitor_weight_outlined))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _heightController, keyboardType: TextInputType.number, decoration: _inputDecoration('ส่วนสูง (ซม.)', Icons.height))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: _bmiController, readOnly: true, decoration: _inputDecoration('ค่า BMI', Icons.analytics_outlined))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _diseaseController,
                      decoration: _inputDecoration('โรคประจำตัว', Icons.medical_services_outlined),
                    ),
                    const SizedBox(height: 16),

                    // 🚬 3. ช่องสลับสถานะสูบบุหรี่ (เพิ่มใหม่ ให้แก้ไขได้)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SwitchListTile(
                        title: const Text('ประวัติการสูบบุหรี่', style: TextStyle(fontWeight: FontWeight.bold, color: slateColor, fontSize: 14)),
                        subtitle: Text(
                          _isSmoker ? '🚬 สูบบุหรี่ (มีความเสี่ยงเพิ่มขึ้น)' : '✨ ไม่สูบบุหรี่ / เลิกสูบแล้ว',
                          style: TextStyle(fontSize: 12, color: _isSmoker ? Colors.red.shade600 : emeraldColor, fontWeight: FontWeight.w600),
                        ),
                        secondary: Icon(Icons.smoking_rooms, color: _isSmoker ? Colors.red : emeraldColor),
                        value: _isSmoker,
                        activeColor: Colors.red,
                        onChanged: (val) {
                          setState(() {
                            _isSmoker = val;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ปุ่มบันทึกพรีเมียม
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emeraldColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('บันทึกข้อมูลโปรไฟล์', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: emeraldColor, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: emeraldColor, width: 1.5)),
    );
  }

  // 🌟 การ์ดแสดงผล Thai CVD Risk Score พร้อม Bar Chart
  Widget _buildThaiCvdRiskCard() {
    final int age = int.tryParse(_ageController.text) ?? 50;
    final bool hasDiabetes = _diseaseController.text.contains('เบาหวาน');
    final double? cholesterol = _latestLab != null ? double.tryParse(_latestLab!['total_cholesterol']?.toString() ?? '') : null;
    bool hasLabData = cholesterol != null && cholesterol > 0;

    // คำนวณความเสี่ยงโดยใช้ ThCvRiskCalculator ตัวจริง (ดึงค่าความดันจริง _latestSystolic และสถานะ _isSmoker)
    final riskResult = ThCvRiskCalculator.calculateRisk(
      age: age,
      gender: 'female', 
      isSmoker: _isSmoker,
      hasDiabetes: hasDiabetes,
      systolicBP: _latestSystolic.toDouble(),
      totalCholesterol: cholesterol,
      useLabData: hasLabData,
    );

    String riskLevel = riskResult['level'];
    String colorCode = riskResult['color'];
    
    Color riskColor = const Color(0xFF10B981);
    double progressVal = 0.3;
    if (colorCode == 'red') {
      riskColor = const Color(0xFFEF4444);
      progressVal = 0.85;
    } else if (colorCode == 'orange') {
      riskColor = const Color(0xFFF97316);
      progressVal = 0.65;
    } else if (colorCode == 'yellow') {
      riskColor = const Color(0xFFF59E0B);
      progressVal = 0.45;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: riskColor.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: riskColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.favorite_rounded, color: riskColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'ประเมินโรคหัวใจ (Thai CVD Risk)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: slateColor),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: hasLabData ? Colors.teal.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: hasLabData ? Colors.teal.shade200 : Colors.blue.shade200),
                ),
                child: Text(
                  hasLabData ? '✨ มีผลแล็บ (แม่นยำสูง)' : '📋 ไม่มีผลแล็บ (ประเมินเบื้องต้น)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: hasLabData ? Colors.teal.shade700 : Colors.blue.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ระดับความเสี่ยงใน 10 ปีข้างหน้า:', style: TextStyle(color: Colors.grey, fontSize: 13)),
              Text(riskLevel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: riskColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 12,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(riskColor),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRiskFactor('อายุ', '$age ปี'),
                _buildRiskFactor('สูบบุหรี่', _isSmoker ? 'สูบ' : 'ไม่สูบ'),
                _buildRiskFactor('ความดันตัวบน', '$_latestSystolic mmHg'),
                _buildRiskFactor('ไขมันรวม (TC)', hasLabData ? '${cholesterol.toStringAsFixed(0)} mg%' : 'ยังไม่มีแล็บ'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskFactor(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: slateColor)),
      ],
    );
  }
}