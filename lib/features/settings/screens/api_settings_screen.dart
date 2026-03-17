import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/cycling_api_service.dart';
import '../../race/providers/race_providers.dart';

class ApiSettingsScreen extends ConsumerStatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  ConsumerState<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends ConsumerState<ApiSettingsScreen> {
  final _controller = TextEditingController();
  bool _testing = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    if (ApiConstants.isCustomKeySet) {
      _controller.text = ApiConstants.serviceKey;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testResult = 'API 키를 입력해주세요';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    await ApiConstants.saveServiceKey(key);
    final api = CyclingApiService();
    final result = await api.testConnection();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSuccess = result.isSuccess;
      _testResult = result.isSuccess ? '연결 성공! API가 정상 동작합니다.' : result.errorMessage;
    });
  }

  Future<void> _saveKey() async {
    final key = _controller.text.trim();
    await ApiConstants.saveServiceKey(key);
    ref.invalidate(raceListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API 키가 저장되었습니다'),
        backgroundColor: Color(0xFF22C55E),
      ),
    );
  }

  Future<void> _resetKey() async {
    _controller.clear();
    await ApiConstants.saveServiceKey('');
    ref.invalidate(raceListProvider);
    if (!mounted) return;
    setState(() {
      _testResult = null;
      _testSuccess = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기본 키로 초기화되었습니다')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('API 설정'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildInfoCard(),
          const SizedBox(height: 20),
          _buildKeyInputSection(),
          const SizedBox(height: 16),
          _buildActionButtons(),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            _buildTestResult(),
          ],
          const SizedBox(height: 24),
          _buildGuideSection(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final isConnected = ApiConstants.isCustomKeySet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF22C55E).withValues(alpha: 0.1)
            : const Color(0xFFFBBF24).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF22C55E).withValues(alpha: 0.3)
              : const Color(0xFFFBBF24).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.info_outline,
            color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFFBBF24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? '사용자 API 키 설정됨' : '기본 API 키 사용 중',
                  style: TextStyle(
                    color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFFBBF24),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected
                      ? '공공데이터포털에서 발급받은 키를 사용합니다'
                      : 'API 연동을 위해 공공데이터포털에서 인증키를 발급받으세요',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '공공데이터 API 인증키 (Decoding)',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Decoding 인증키를 붙여넣으세요',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFBBF24)),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste, color: Color(0xFFFBBF24), size: 20),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _controller.text = data!.text!;
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: Text(_testing ? '테스트 중...' : '연결 테스트'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saveKey,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('저장'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _resetKey,
          icon: const Icon(Icons.restart_alt, color: Color(0xFFEF4444)),
          tooltip: '초기화',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildTestResult() {
    final isOk = _testSuccess == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.error_outline,
            color: isOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _testResult ?? '',
              style: TextStyle(
                color: isOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'API 키 발급 방법',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _guideStep('1', '공공데이터포털 회원가입', 'www.data.go.kr 접속 후 회원가입'),
          _guideStep('2', '경륜 API 검색', '"경주사업총괄본부 경륜" 검색'),
          _guideStep('3', 'API 활용 신청', '경주결과, 선수정보 등 필요한 API 활용 신청'),
          _guideStep('4', '인증키 확인', '마이페이지 > Open API > 인증키 확인\n(일반 인증키 Decoding 사용)'),
          _guideStep('5', '키 입력 및 테스트', '위 입력란에 붙여넣기 후 연결 테스트'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFFFBBF24), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '신청 후 승인까지 최대 1~2시간 소요될 수 있습니다',
                    style: TextStyle(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideStep(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              num,
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
