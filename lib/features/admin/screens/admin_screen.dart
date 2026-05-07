import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_auth_provider.dart';

const Color _kBg = Color(0xFF0D1117);
const Color _kCard = Color(0xFF161B22);
const Color _kBorder = Color(0xFF30363D);
const Color _kPrimary = Color(0xFF1565C0);
const Color _kAccent = Color(0xFFFBBF24);

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = '비밀번호를 입력해 주세요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final ok = await ref.read(adminAuthProvider.notifier).login(password);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (!ok) {
        _errorMessage = '비밀번호가 일치하지 않습니다.';
      } else {
        _passwordController.clear();
      }
    });

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('관리자 로그인 성공! 모든 잠금이 해제되었습니다.'),
          backgroundColor: Color(0xFF22C55E),
        ),
      );
    }
  }

  Future<void> _onLogout() async {
    await ref.read(adminAuthProvider.notifier).logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('관리자 로그아웃되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(adminAuthProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '관리자 페이지',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: isAdmin ? _buildLoggedInView() : _buildLoginView(),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return ListView(
      children: [
        _buildHeader(
          icon: Icons.shield_outlined,
          title: '관리자 로그인',
          description: '비밀번호를 입력하면 모든 잠금된 기능을 이용할 수 있습니다.',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '비밀번호',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _onSubmit(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: '관리자 비밀번호 입력',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade600,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w400,
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.25),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kPrimary, width: 1.6),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _onSubmit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kPrimary.withValues(alpha: 0.4),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('로그인'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedInView() {
    return ListView(
      children: [
        _buildHeader(
          icon: Icons.verified_user_rounded,
          title: '관리자 로그인 상태',
          description: '모든 잠금 기능이 해제되었습니다.\nAI 추천, 추천 vs 실제 비교 등을 자유롭게 이용하세요.',
          iconColor: const Color(0xFF22C55E),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: _kAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '잠금 해제 항목',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _UnlockedItem(label: 'AI 추천 탭'),
              const _UnlockedItem(label: '추천 vs 실제 비교'),
              const _UnlockedItem(label: '구독 전용 기능 전체'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('로그아웃'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            minimumSize: const Size.fromHeight(48),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({
    required IconData icon,
    required String title,
    required String description,
    Color? iconColor,
  }) {
    final color = iconColor ?? _kAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _UnlockedItem extends StatelessWidget {
  const _UnlockedItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF22C55E),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
