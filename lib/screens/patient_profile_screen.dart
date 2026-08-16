import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/vital_repository.dart';
import '../services/th_cv_risk_calculator.dart';
import '../widgets/bmi_bar_chart.dart';

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

  // 📍 ตัวแปรระบบใหม่สำหรับ TDEE & Activity
  String _gender = 'ชาย';
  String _activityLevel = 'sedentary';
  double _bmr = 0.0;
  double _tdee = 0.0;

  bool _isSmoker = false;
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _latestLab;
  int _latestSystolic = 120;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  final Map<String, Map<String, dynamic>> _activityOptions = {
    'sedentary': {
      'label': 'นั่งทำงานอยู่กับที่ (ไม่ออกกำลังกาย)',
      'multiplier': 1.2,
    },
    'light': {
      'label': 'ออกกำลังกายเบาๆ (1-3 วัน/สัปดาห์)',
      'multiplier': 1.375,
    },
    'moderate': {
      'label': 'ออกกำลังกายปานกลาง (3-5 วัน/สัปดาห์)',
      'multiplier': 1.55,
    },
    'active': {
      'label': 'ออกกำลังกายหนัก (6-7 วัน/สัปดาห์)',
      'multiplier': 1.725,
    },
    'very_active': {
      'label': 'ใช้แรงงานหนัก / ซ้อมกีฬาหนัก',
      'multiplier': 1.9,
    },
  };

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
          _weightController.text =
              (profile['weight_kg'] ?? profile['weight'] ?? '').toString();
          _heightController.text =
              (profile['height_cm'] ?? profile['height'] ?? '').toString();
          _bmiController.text = (profile['bmi'] ?? '').toString();
          _diseaseController.text =
              profile['underlying_diseases'] ?? profile['diseases'] ?? '';
          _isSmoker = profile['smokes'] == true || profile['smokers'] == true;
          _gender = profile['gender']?.toString() ?? 'ชาย';
          _activityLevel = profile['activity_level']?.toString() ?? 'sedentary';
          if (!_activityOptions.containsKey(_activityLevel)) {
            _activityLevel = 'sedentary';
          }

          _calculateMetrics();
          _isLoading = false;
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
            _latestSystolic =
                (vitals.first['systolic'] as num?)?.toInt() ?? 120;
          }
        });
      }
    } catch (e) {
      debugPrint('Background data fetch error: $e');
    }
  }

  // 📍 คำนวณสูตร BMI, BMR, TDEE อัตโนมัติ (Mifflin-St Jeor Formula)
  void _calculateMetrics() {
    final weight = double.tryParse(_weightController.text) ?? 0.0;
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final age = int.tryParse(_ageController.text) ?? 0;

    double bmi = 0.0;
    if (height > 0 && weight > 0) {
      final heightInMeter = height / 100;
      bmi = weight / (heightInMeter * heightInMeter);
      _bmiController.text = bmi.toStringAsFixed(1);
    }

    double bmr = 0.0;
    if (weight > 0 && height > 0 && age > 0) {
      if (_gender == 'ชาย') {
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
      } else {
        bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
      }
    }

    final multiplier =
        _activityOptions[_activityLevel]?['multiplier'] as double? ?? 1.2;
    final tdee = bmr * multiplier;

    _bmr = bmr;
    _tdee = tdee;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    _calculateMetrics();

    final fName = _fNameController.text.trim();
    final lName = _lNameController.text.trim();
    final weight = double.tryParse(_weightController.text) ?? 0.0;
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final age = int.tryParse(_ageController.text) ?? 0;
    final bmi = double.tryParse(_bmiController.text) ?? 0.0;

    final updateData = {
      'first_name': fName,
      'last_name': lName,
      'name': '$fName $lName',
      'age': age,
      'gender': _gender,
      'weight': weight,
      'weight_kg': weight,
      'height': height,
      'height_cm': height,
      'bmi': bmi,
      'bmr': double.parse(_bmr.toStringAsFixed(1)),
      'tdee': double.parse(_tdee.toStringAsFixed(1)),
      'activity_level': _activityLevel,
      'underlying_diseases': _diseaseController.text.trim(),
      'smokes': _isSmoker,
    };

    // 1. บันทึกลง Local (SharedPreferences)
    await _profileService.updateLocalProfile(updateData);

    // 2. บันทึกลง Supabase (ตาราง patients)
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null && patientId.isNotEmpty) {
        await Supabase.instance.client.from('patients').update({
          'first_name': updateData['first_name'],
          'last_name': updateData['last_name'],
          'name': updateData['name'],
          'age': updateData['age'],
          'gender': updateData['gender'],
          'weight_kg': updateData['weight_kg'],
          'height_cm': updateData['height_cm'],
          'bmi': updateData['bmi'],
          'bmr': updateData['bmr'],
          'tdee': updateData['tdee'],
          'activity_level': updateData['activity_level'],
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
          content:
              const Text('บันทึกข้อมูลโปรไฟล์และเป้าหมายพลังงานเรียบร้อยแล้ว'),
          backgroundColor: emeraldColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        title: const Text('โปรไฟล์ผู้ป่วย & ข้อมูลสุขภาพ',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: emeraldColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 🌟 1. การ์ดพลังงานรวม BMR & TDEE (Scrollable Dashboard)
                    _buildEnergySummaryCard(),
                    const SizedBox(height: 16),

                    // 🌟 2. การ์ดประเมิน Thai CVD Risk (คำนวณตามเพศจริง)
                    _buildThaiCvdRiskCard(),
                    const SizedBox(height: 16),

                    // 📝 3. ฟอร์มข้อมูลส่วนตัวและสุขภาพ
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ข้อมูลร่างกายและกิจกรรม',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: slateColor)),
                            const Divider(height: 24),

                            // ชื่อ - นามสกุล
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _fNameController,
                                    decoration: _inputDecoration(
                                        'ชื่อ', Icons.person_outline),
                                    validator: (v) => v!.trim().isEmpty
                                        ? 'กรุณากรอกชื่อ'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _lNameController,
                                    decoration: _inputDecoration(
                                        'นามสกุล', Icons.person),
                                    validator: (v) => v!.trim().isEmpty
                                        ? 'กรุณากรอกนามสกุล'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // เพศกำเนิด & อายุ
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _gender,
                                    decoration: _inputDecoration(
                                        'เพศกำเนิด', Icons.wc_outlined),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'ชาย', child: Text('ชาย')),
                                      DropdownMenuItem(
                                          value: 'หญิง', child: Text('หญิง')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _gender = val;
                                          _calculateMetrics();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _ageController,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                        'อายุ (ปี)', Icons.cake_outlined),
                                    onChanged: (_) =>
                                        setState(() => _calculateMetrics()),
                                    validator: (v) =>
                                        v!.trim().isEmpty ? 'ระบุอายุ' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // น้ำหนัก & ส่วนสูง & BMI
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _weightController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                        'น้ำหนัก (กก.)',
                                        Icons.monitor_weight_outlined),
                                    onChanged: (_) =>
                                        setState(() => _calculateMetrics()),
                                    validator: (v) => v!.trim().isEmpty
                                        ? 'ระบุน้ำหนัก'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _heightController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                        'ส่วนสูง (ซม.)', Icons.height),
                                    onChanged: (_) =>
                                        setState(() => _calculateMetrics()),
                                    validator: (v) => v!.trim().isEmpty
                                        ? 'ระบุส่วนสูง'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _bmiController,
                                    readOnly: true,
                                    decoration: _inputDecoration(
                                        'ค่า BMI', Icons.analytics_outlined),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 📊 กราฟ BMI Bar Chart
                            if (double.tryParse(_bmiController.text) != null &&
                                double.parse(_bmiController.text) > 0) ...[
                              BmiBarChart(
                                  bmi: double.parse(_bmiController.text)),
                              const SizedBox(height: 16),
                            ],

                            // ระดับกิจกรรมประจำวัน (Activity Level)
                            DropdownButtonFormField<String>(
                              value: _activityLevel,
                              isExpanded: true,
                              decoration: _inputDecoration(
                                  'กิจกรรมและการออกกำลังกาย',
                                  Icons.directions_run_rounded),
                              items: _activityOptions.entries.map((e) {
                                return DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value['label'],
                                      style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _activityLevel = val;
                                    _calculateMetrics();
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            // โรคประจำตัว
                            TextFormField(
                              controller: _diseaseController,
                              decoration: _inputDecoration('โรคประจำตัว',
                                  Icons.medical_services_outlined),
                            ),
                            const SizedBox(height: 16),

                            // สลับสถานะสูบบุหรี่
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: SwitchListTile(
                                title: const Text('ประวัติการสูบบุหรี่',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: slateColor,
                                        fontSize: 14)),
                                subtitle: Text(
                                  _isSmoker
                                      ? '🚬 สูบบุหรี่ (มีความเสี่ยงเพิ่มขึ้น)'
                                      : '✨ ไม่สูบบุหรี่ / เลิกสูบแล้ว',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _isSmoker
                                          ? Colors.red.shade600
                                          : emeraldColor,
                                      fontWeight: FontWeight.w600),
                                ),
                                secondary: Icon(Icons.smoking_rooms,
                                    color:
                                        _isSmoker ? Colors.red : emeraldColor),
                                value: _isSmoker,
                                activeColor: Colors.red,
                                onChanged: (val) {
                                  setState(() {
                                    _isSmoker = val;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ปุ่มบันทึกโปรไฟล์
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emeraldColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('บันทึกข้อมูลและเป้าหมายพลังงาน',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 32),
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
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: emeraldColor, width: 1.5)),
    );
  }

  // 🌟 การ์ดสรุปพลังงาน BMR & TDEE (Scrollable Modular Card)
  Widget _buildEnergySummaryCard() {
    final deficitTarget = (_tdee - 400).clamp(1200.0, 9999.0);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [emeraldColor.withOpacity(0.12), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_fire_department_rounded,
                    color: Colors.deepOrange, size: 26),
                SizedBox(width: 8),
                Text('เป้าหมายพลังงานรายวัน (TDEE)',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: slateColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BMR (เผาผลาญพื้นฐาน)',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('${_bmr.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: slateColor)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TDEE (ใช้พลังงานรวม)',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('${_tdee.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: emeraldColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'เป้าหมายลดน้ำหนักที่ปลอดภัย: ไม่เกิน ${deficitTarget.toStringAsFixed(0)} kcal/วัน',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🌟 การ์ดแสดงผล Thai CVD Risk Score พร้อม Bar Chart
  Widget _buildThaiCvdRiskCard() {
    final int age = int.tryParse(_ageController.text) ?? 50;
    final bool hasDiabetes = _diseaseController.text.contains('เบาหวาน');
    final double? cholesterol = _latestLab != null
        ? double.tryParse(_latestLab!['total_cholesterol']?.toString() ?? '')
        : null;
    bool hasLabData = cholesterol != null && cholesterol > 0;

    // 📍 ส่งค่าพารามิเตอร์ตรงตาม Class ThCvRiskCalculator ในโปรเจกต์ของคุณเป๊ะ 100%
    final riskResult = ThCvRiskCalculator.calculateRisk(
      age: age,
      gender: _gender == 'ชาย' ? 'male' : 'female', // แปลงเพศให้ตรงระบบ
      isSmoker: _isSmoker,
      hasDiabetes: hasDiabetes,
      systolicBP: _latestSystolic.toDouble(),
      totalCholesterol: cholesterol,
      useLabData: hasLabData,
    );

    String riskLevel = riskResult['level'] ?? 'ไม่ระบุ';
    String colorCode = riskResult['color'] ?? 'green';

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: riskColor.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.favorite_rounded,
                        color: riskColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ประเมินโรคหัวใจ (Thai CVD Risk)',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: slateColor),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasLabData ? Colors.teal.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: hasLabData
                          ? Colors.teal.shade200
                          : Colors.blue.shade200),
                ),
                child: Text(
                  hasLabData ? '✨ มีผลแล็บ' : '📋 ไม่มีผลแล็บ',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: hasLabData
                          ? Colors.teal.shade700
                          : Colors.blue.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ระดับความเสี่ยงใน 10 ปีข้างหน้า:',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(riskLevel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: riskColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(riskColor),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
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
                _buildRiskFactor(
                    'ไขมันรวม (TC)',
                    hasLabData
                        ? '${cholesterol.toStringAsFixed(0)} mg%'
                        : 'ยังไม่มีแล็บ'),
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
        Text(val,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: slateColor)),
      ],
    );
  }
}
