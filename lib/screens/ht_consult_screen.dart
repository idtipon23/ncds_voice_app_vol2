import 'package:flutter/material.dart';
import '../services/patient_profile_service.dart';
import '../services/ht_consult_service.dart';

class HtConsultScreen extends StatefulWidget {
  const HtConsultScreen({super.key});

  @override
  State<HtConsultScreen> createState() => _HtConsultScreenState();
}

class _HtConsultScreenState extends State<HtConsultScreen> {
  final _profileService = PatientProfileService();
  final _consultService = HtConsultService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai',
      'text':
          'สวัสดีค่ะ มีข้อสงสัยเกี่ยวกับโรคความดัน การทานยา การคุมอาหาร หรือต้องการคำแนะนำตามแนวทาง HT Guideline 2567 สอบถามหมอ AI ได้เลยนะคะ 😊',
      'time': DateTime.now(),
    }
  ];

  bool _isSending = false;
  Map<String, dynamic>? _profileData;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileService.getProfile();
    setState(() => _profileData = profile);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    _textController.clear();
    setState(() {
      _messages.add({'sender': 'user', 'text': text, 'time': DateTime.now()});
      _isSending = true;
    });
    _scrollToBottom();

    final result = await _consultService.askConsult(
      userQuery: text,
      profileData: _profileData,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({
          'sender': 'ai',
          'text': result['answer'] ?? 'ขออภัย ไม่สามารถประมวลผลคำตอบได้',
          'time': DateTime.now(),
          'hasWarning': result['has_warning_sign'] == true,
          'urgency': result['urgency_level'],
        });
      });
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('ปรึกษาหมอ AI (HT Consult)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: emeraldColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ⚠️ Sticky Disclaimer Banner (ความปลอดภัยทางการแพทย์)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'คำแนะนำอ้างอิงตาม HT Guideline 2567 เพื่อการดูแลตนเองเบื้องต้น หากมีอาการวิกฤตให้พบแพทย์ทันที',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          // 💬 รายการข้อความแชต
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                final isWarning = msg['hasWarning'] == true;

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? emeraldColor
                          : (isWarning ? Colors.red.shade50 : Colors.white),
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser
                            ? const Radius.circular(0)
                            : const Radius.circular(16),
                        bottomLeft: !isUser
                            ? const Radius.circular(0)
                            : const Radius.circular(16),
                      ),
                      border: isUser
                          ? null
                          : Border.all(
                              color: isWarning
                                  ? Colors.red.shade300
                                  : Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isWarning
                                    ? Icons.warning_amber_rounded
                                    : Icons.medical_services_rounded,
                                size: 16,
                                color: isWarning ? Colors.red : emeraldColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isWarning
                                    ? 'คำเตือนฉุกเฉิน'
                                    : 'ผู้ช่วย AI ความดัน',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isWarning ? Colors.red : emeraldColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          msg['text'],
                          style: TextStyle(
                            fontSize: 14,
                            color: isUser
                                ? Colors.white
                                : (isWarning
                                    ? Colors.red.shade900
                                    : slateColor),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isSending)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: emeraldColor)),
                  SizedBox(width: 8),
                  Text('หมอ AI กำลังพิมพ์คำตอบ...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

          // ⌨️ ช่องพิมพ์ส่งคำถาม
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2)),
            ]),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ถาม เช่น ลืมกินยามื้อเช้าทำไงดี?',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _handleSendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: emeraldColor,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _handleSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
