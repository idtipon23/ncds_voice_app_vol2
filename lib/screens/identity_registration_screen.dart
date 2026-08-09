import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import 'home_screen.dart';

class IdentityRegistrationScreen extends StatefulWidget {
  const IdentityRegistrationScreen({super.key});

  @override
  State<IdentityRegistrationScreen> createState() =>
      _IdentityRegistrationScreenState();
}

class _IdentityRegistrationScreenState
    extends State<IdentityRegistrationScreen> {
  final _supabase = Supabase.instance.client;
  final _hnController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _profileService = PatientProfileService();

  bool _isLoading = false;
  bool _isFetchingHospitals = true;
  bool _isExistingPatient = true; // Default: ผู้ป่วยเก่า (มี HN)
  List<Map<String, dynamic>> _hospitals = [];
  String? _selectedHospitalId;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _fetchHospitalsAndAutoFill();
  }

  @override
  void dispose() {
    _hnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  /// 📍 ดึงรายชื่อโรงพยาบาล พร้อม Auto-fill ข้อมูล Smart HN Memory
  Future<void> _fetchHospitalsAndAutoFill() async {
    setState(() => _isFetchingHospitals = true);
    try {
      final response = await _supabase
          .from('hospitals')
          .select('id, name, code')
          .order('name');

      final hospitalList = List<Map<String, dynamic>>.from(response);

      final lastInfo = await _profileService.getLastLoginInfo();
      final savedHn = lastInfo['hn'] ?? '';
      final savedHospitalId = lastInfo['hospital_id'] ?? '';

      setState(() {
        _hospitals = hospitalList;
        if (hospitalList.isNotEmpty) {
          _selectedHospitalId = hospitalList.first['id'].toString();
        }

        if (savedHospitalId.isNotEmpty &&
            hospitalList.any((h) => h['id'].toString() == savedHospitalId)) {
          _selectedHospitalId = savedHospitalId;
        }

        if (savedHn.isNotEmpty) {
          _hnController.text = savedHn;
          _isExistingPatient = true;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error fetching hospitals: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingHospitals = false);
      }
    }
  }

  /// 📍 บันทึก/ยืนยันตัวตน (พร้อมระบบป้องกันค้าง Timeout)
  Future<void> _saveIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHospitalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกสถานพยาบาล')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = _supabase.auth.currentUser;

      if (_isExistingPatient) {
        // ==================== ผู้ป่วยเก่า ====================
        String hnInput = _hnController.text.trim();
        final hn = hnInput.startsWith('HN-') || hnInput.startsWith('hn-') 
            ? hnInput.toUpperCase() 
            : 'HN-$hnInput';

        debugPrint('🔍 แปลงร่าง HN เป็น: "$hn" เพื่อค้นหาในระบบ');

        // 1. ค้นหาผู้ป่วยใน Supabase (พร้อม Timeout ป้องกันแอปค้างนิ่ง)
        final existingPatient = await _supabase
            .from('patients')
            .select()
            .eq('hn', hn)
            .eq('hospital_id', _selectedHospitalId!)
            .maybeSingle()
            .timeout(const Duration(seconds: 10), onTimeout: () {
              throw Exception('การเชื่อมต่อกับเซิร์ฟเวอร์ใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง');
            });

        if (existingPatient == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ไม่พบข้อมูลผู้ป่วยรหัส HN: $hn ในสถานพยาบาลที่เลือก'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // 2. ผูกบัญชี LINE ล่าสุดเข้ากับข้อมูลผู้ป่วยเดิม
        if (currentUser != null) {
          final updateResponse = await _supabase
              .from('patients')
              .update({'id': currentUser.id})
              .eq('hn', hn)
              .eq('hospital_id', _selectedHospitalId!)
              .select()
              .single()
              .timeout(const Duration(seconds: 10));
          
          await _profileService.saveProfile(updateResponse);
        }

      } else {
        // ==================== ผู้ป่วยใหม่ ====================
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final newHn = _hnController.text.trim().isNotEmpty
            ? _hnController.text.trim()
            : 'HN-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

        final newPatientData = {
          'id': currentUser?.id,
          'hospital_id': _selectedHospitalId,
          'hn': newHn,
          'first_name': firstName,
          'last_name': lastName,
          'name': '$firstName $lastName',
        };

        final inserted = await _supabase
            .from('patients')
            .insert(newPatientData)
            .select()
            .single()
            .timeout(const Duration(seconds: 10));

        await _profileService.saveProfile(inserted);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      debugPrint('❌ เกิดข้อผิดพลาด: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false); // ปลดล็อกปุ่มเสมอไม่ว่าจะสำเร็จหรือพัง
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'ยืนยันตัวตน / ลงทะเบียนผู้ป่วย',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: emeraldColor,
        elevation: 0,
      ),
      body: _isFetchingHospitals
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toggle สลับโหมด
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _isExistingPatient = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _isExistingPatient ? emeraldColor : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'ผู้ป่วยเก่า (มี HN)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _isExistingPatient ? Colors.white : slateColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _isExistingPatient = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !_isExistingPatient ? emeraldColor : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'ผู้ป่วยใหม่ (ไม่มี HN)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: !_isExistingPatient ? Colors.white : slateColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // เลือกสถานพยาบาล
                    const Text('สถานพยาบาล / คลินิก', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: slateColor)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedHospitalId,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.local_hospital, color: emeraldColor),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _hospitals.map((hospital) {
                        return DropdownMenuItem<String>(
                          value: hospital['id'].toString(),
                          child: Text(hospital['name'] ?? 'ไม่ระบุชื่อ', style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedHospitalId = val),
                      validator: (val) => val == null ? 'กรุณาเลือกสถานพยาบาล' : null,
                    ),
                    const SizedBox(height: 20),

                    // ฟอร์มกรอก HN หรือ ข้อมูลผู้ป่วยใหม่
                    if (_isExistingPatient) ...[
                      const Text('รหัส HN (เลขประจำตัวผู้ป่วย)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: slateColor)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _hnController,
                        decoration: InputDecoration(
                          hintText: 'เช่น 16914',
                          prefixIcon: const Icon(Icons.badge, color: emeraldColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'กรุณากรอกรหัส HN' : null,
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      const Text('ชื่อผู้ป่วย', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: slateColor)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _firstNameController,
                        decoration: InputDecoration(
                          hintText: 'กรอกชื่อจริง',
                          prefixIcon: const Icon(Icons.person, color: emeraldColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text('นามสกุล', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: slateColor)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _lastNameController,
                        decoration: InputDecoration(
                          hintText: 'กรอกนามสกุล',
                          prefixIcon: const Icon(Icons.person_outline, color: emeraldColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'กรุณากรอกนามสกุล' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text('รหัส HN (ระบุเอง หรือเว้นว่างไว้)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: slateColor)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _hnController,
                        decoration: InputDecoration(
                          hintText: 'เว้นว่างไว้หากต้องการให้แอปสร้างให้อัตโนมัติ',
                          prefixIcon: const Icon(Icons.pin, color: emeraldColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ปุ่มยืนยัน
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emeraldColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        onPressed: _isLoading ? null : _saveIdentity,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _isExistingPatient ? "ยืนยันและเข้าสู่ระบบ" : "ลงทะเบียนและเริ่มต้นใช้งาน",
                                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}