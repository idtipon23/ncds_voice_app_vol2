import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart'; 
import '../services/pdf_export_service.dart'; 
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart'; 
import '../services/vital_repository.dart';

enum HistoryViewState { loading, success, empty, error }
enum DateRangeFilter { last7Days, last1Month, last3Months }
enum DisplayTab { vitals, labs }

class HealthHistoryScreen extends StatefulWidget {
  const HealthHistoryScreen({super.key});

  @override
  State<HealthHistoryScreen> createState() => _HealthHistoryScreenState();
}

class _HealthHistoryScreenState extends State<HealthHistoryScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final VitalRepository _vitalRepository = VitalRepository();
  final PatientDatabaseService _dbService = PatientDatabaseService();
  final supabase = Supabase.instance.client;

  HistoryViewState _viewState = HistoryViewState.loading;
  DateRangeFilter _selectedFilter = DateRangeFilter.last7Days;
  DisplayTab _currentTab = DisplayTab.vitals;

  List<Map<String, dynamic>> _vitalHistory = [];
  List<Map<String, dynamic>> _labHistory = [];
  String _errorMessage = '';

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _viewState = HistoryViewState.loading);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        setState(() {
          _errorMessage = 'ไม่พบข้อมูลประจำตัวผู้ป่วย';
          _viewState = HistoryViewState.error;
        });
        return;
      }

      // ดึงข้อมูลสัญญาณชีพตาม Filter
      List<Map<String, dynamic>> vitals = [];
      switch (_selectedFilter) {
        case DateRangeFilter.last7Days:
          vitals = await _vitalRepository.getLast7Days(patientId);
          break;
        case DateRangeFilter.last1Month:
          vitals = await _vitalRepository.getLast1Month(patientId);
          break;
        case DateRangeFilter.last3Months:
          vitals = await _vitalRepository.getLast3Months(patientId);
          break;
      }

      // ดึงประวัติผลแล็บ
      final labs = await _dbService.getLabResults(patientId);
      setState(() {
        _vitalHistory = vitals;
        _labHistory = labs;
        _viewState = (_vitalHistory.isEmpty && _labHistory.isEmpty)
            ? HistoryViewState.empty
            : HistoryViewState.success;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
        _viewState = HistoryViewState.error;
      });
    }
  }

  Future<void> _exportPdfReport() async {
    try {
      final profile = await _profileService.getProfile();
      final patientName = profile != null ? '${profile['first_name']} ${profile['last_name']}' : 'ผู้ป่วย';
      final hn = profile?['hn'] ?? 'N/A';
      final age = profile?['age'];
      final weight = profile?['weight'];
      final height = profile?['height'];
      final diseases = profile?['underlying_diseases'];
      String filterText = '7 วันย้อนหลัง';
      if (_selectedFilter == DateRangeFilter.last1Month) filterText = '1 เดือนย้อนหลัง';
      if (_selectedFilter == DateRangeFilter.last3Months) filterText = '3 เดือนย้อนหลัง';

      final pdfBytes = await PdfExportService.generateHealthReport(
        patientName: patientName,
        hn: hn,
        age: age,
        weight: weight,
        height: height,
        underlyingDiseases: diseases,
        hospitalName: "hospitalName",
        filterTitle: filterText,
        vitalHistory: _vitalHistory,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Health_Report_$hn.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการพิมพ์ PDF: $e')));
      }
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('เอกสารใบผลตรวจ', style: TextStyle(fontSize: 16)),
              backgroundColor: Colors.white,
              foregroundColor: slateColor,
              elevation: 0,
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Column(
                    children: [
                      Icon(Icons.broken_image, size: 60, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('ไม่สามารถโหลดรูปภาพได้'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('ประวัติสุขภาพและผลตรวจ', style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: slateColor), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: emeraldColor),
            onPressed: _vitalHistory.isNotEmpty ? _exportPdfReport : null,
            tooltip: 'พิมพ์รายงาน PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('สัญญาณชีพ (Vitals)')),
                        selected: _currentTab == DisplayTab.vitals,
                        selectedColor: emeraldColor.withOpacity(0.2),
                        labelStyle: TextStyle(color: _currentTab == DisplayTab.vitals ? emeraldColor : slateColor, fontWeight: FontWeight.bold),
                        onSelected: (selected) {
                          if (selected) setState(() => _currentTab = DisplayTab.vitals);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('ผลแล็บ (Lab Reports)')),
                        selected: _currentTab == DisplayTab.labs,
                        selectedColor: emeraldColor.withOpacity(0.2),
                        labelStyle: TextStyle(color: _currentTab == DisplayTab.labs ? emeraldColor : slateColor, fontWeight: FontWeight.bold),
                        onSelected: (selected) {
                          if (selected) setState(() => _currentTab = DisplayTab.labs);
                        },
                      ),
                    ),
                  ],
                ),
                if (_currentTab == DisplayTab.vitals) 
                  ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildFilterChip('7 วันล่าสุด', DateRangeFilter.last7Days),
                        _buildFilterChip('1 เดือนล่าสุด', DateRangeFilter.last1Month),
                        _buildFilterChip('3 เดือนล่าสุด', DateRangeFilter.last3Months),
                      ],
                    ),
                  ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, DateRangeFilter filter) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : slateColor)),
      selected: isSelected,
      selectedColor: emeraldColor,
      backgroundColor: Colors.grey.shade100,
      showCheckmark: false,
      onSelected: (bool selected) {
        if (selected) {
          setState(() => _selectedFilter = filter);
          _loadData();
        }
      },
    );
  }

  Widget _buildMainContent() {
    if (_viewState == HistoryViewState.loading) {
      return const Center(child: CircularProgressIndicator(color: emeraldColor));
    }

    if (_viewState == HistoryViewState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 60),
              const SizedBox(height: 16),
              Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: emeraldColor),
                onPressed: _loadData,
                child: const Text('ลองใหม่อีกครั้ง', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentTab == DisplayTab.vitals) {
      if (_vitalHistory.isEmpty) {
        return const Center(child: Text('ไม่พบประวัติค่าวัดสัญญาณชีพในช่วงเวลานี้', style: TextStyle(color: Colors.grey)));
      }

      double avgSys = 0;
      double avgDia = 0;
      double avgPulse = 0;
      int pulseCount = 0;
      for (var item in _vitalHistory) {
        avgSys += (item['systolic'] as num?)?.toDouble() ?? 0;
        avgDia += (item['diastolic'] as num?)?.toDouble() ?? 0;
        final p = (item['pulse'] as num?)?.toDouble();
        if (p != null && p > 0) {
          avgPulse += p;
          pulseCount++;
        }
      }
      if (_vitalHistory.isNotEmpty) {
        avgSys = avgSys / _vitalHistory.length;
        avgDia = avgDia / _vitalHistory.length;
        if (pulseCount > 0) avgPulse = avgPulse / pulseCount;
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vitalHistory.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildPremiumGradientSummaryCard(avgSys, avgDia, avgPulse);
          }

          final item = _vitalHistory[index - 1];

          final int? sys = (item['systolic'] as num?)?.toInt();
          final int? dia = (item['diastolic'] as num?)?.toInt();
          final int? pulse = (item['pulse'] as num?)?.toInt();

          final String recordedAt = item['recorded_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? '';
          final String urgency = item['urgency_level']?.toString() ?? 'NORMAL';

          Color statusColor = emeraldColor;
          if (urgency == 'YELLOW' || urgency == 'MODERATE') {
            statusColor = Colors.amber.shade700;
          } else if (urgency == 'ELEVATED' || urgency == 'HIGH') {
            statusColor = Colors.orange;
          } else if (urgency == 'CRITICAL') {
            statusColor = Colors.redAccent;
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(recordedAt, style: const TextStyle(fontWeight: FontWeight.bold, color: slateColor)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: Text(urgency, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ความดัน: ${sys ?? '-'}/${dia ?? '-'} mmHg', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text('ชีพจร: ${pulse ?? '-'} bpm', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      if (_labHistory.isEmpty) {
        return const Center(child: Text('ยังไม่มีประวัติผลตรวจแล็บในระบบ', style: TextStyle(color: Colors.grey)));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _labHistory.length,
        itemBuilder: (context, index) {
          final lab = _labHistory[index];

          final double? tc = (lab['total_cholesterol'] as num?)?.toDouble();
          final double? hdl = (lab['hdl'] as num?)?.toDouble();
          final double? ldl = (lab['ldl'] as num?)?.toDouble();
          final double? fbs = (lab['fasting_blood_sugar'] as num?)?.toDouble();
          final double? cr = (lab['creatinine'] as num?)?.toDouble();

          final String testDate = lab['test_date']?.toString().substring(0, 10) ?? '';
          final String? imageUrl = lab['image_url'];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ผลตรวจแล็บ (Lab Report)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: slateColor)),
                      Text(testDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const Divider(height: 16),
                  _buildLabRow('Total Cholesterol', tc, 'mg/dL'),
                  _buildLabRow('HDL', hdl, 'mg/dL'),
                  _buildLabRow('LDL', ldl, 'mg/dL'),
                  _buildLabRow('Fasting Blood Sugar (FBS)', fbs, 'mg/dL'),
                  _buildLabRow('Creatinine', cr, 'mg/dL'),
                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: emeraldColor, side: const BorderSide(color: emeraldColor)),
                        onPressed: () => _showImageDialog(imageUrl),
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text('ดูใบผลตรวจแล็บที่อัปโหลด'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildPremiumGradientSummaryCard(double avgSys, double avgDia, double avgPulse) {
    String title = 'ภาพรวมความดัน 7 วันล่าสุด';
    if (_selectedFilter == DateRangeFilter.last1Month) title = 'ภาพรวมความดัน 1 เดือนล่าสุด';
    if (_selectedFilter == DateRangeFilter.last3Months) title = 'ภาพรวมความดัน 3 เดือนล่าสุด';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: emeraldColor.withOpacity(0.35),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
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
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ค่าเฉลี่ย (Average)',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAverageItem('ความดันตัวบน', avgSys > 0 ? avgSys.toStringAsFixed(0) : '-', 'mmHg'),
              Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
              _buildAverageItem('ความดันตัวล่าง', avgDia > 0 ? avgDia.toStringAsFixed(0) : '-', 'mmHg'),
              Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
              _buildAverageItem('ชีพจร', avgPulse > 0 ? avgPulse.toStringAsFixed(0) : '-', 'bpm'),
            ],
          ),
          const SizedBox(height: 20),
          
          // บาร์ชาร์ตพรีเมียม (ปรับสีความคมชัดสูง แยกตามระดับค่าความดันจริงอย่างชัดเจน)
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _vitalHistory.take(7).map((item) {
                final sysVal = (item['systolic'] as num?)?.toDouble() ?? 120;
                double factor = (sysVal / 180.0).clamp(0.2, 1.0);
                
                // กำหนดสีและคอนทราสต์แถบ Bar ให้ชัดเจนแยกตามระดับความดัน (ต่ำ, ปกติ, สูง, วิกฤต)
                Color barColor = Colors.white;
                if (sysVal < 90) {
                  barColor = const Color(0xFF93C5FD); // สีฟ้า (ความดันต่ำ)
                } else if (sysVal >= 160) {
                  barColor = const Color(0xFFEF4444); // สีแดงสด (วิกฤต)
                } else if (sysVal >= 140) {
                  barColor = const Color(0xFFF59E0B); // สีส้ม (สูง)
                } else if (sysVal >= 120) {
                  barColor = const Color(0xFFFDE047); // สีเหลืองสด (สูงกว่าปกติ)
                } else {
                  barColor = Colors.white; // สีขาว (ปกติ)
                }

                return _buildBarItem(factor, barColor);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageItem(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBarItem(double heightFactor, Color barColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            width: 12,
            height: 60 * heightFactor,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '•',
          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildLabRow(String title, dynamic value, String unit) {
    if (value == null) return const SizedBox.shrink();
    final String displayVal = (value is num) ? value.toStringAsFixed(1) : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '$displayVal ', style: const TextStyle(fontWeight: FontWeight.bold, color: slateColor, fontSize: 15)),
                TextSpan(text: unit, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}