import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_state.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_viewmodel.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loginViewModelProvider);
    final viewModel = ref.read(loginViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: JxufeTheme.backgroundColor,
      body: Stack(
        children: [
          // 背景装饰元素（保持不变）
          _buildBackgroundDecorations(),
          SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 60),
                  _buildLoginCard(context, state, viewModel),
                  const Spacer(),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecorations() {
    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: JxufeTheme.primaryColor.withAlpha(26),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(100),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: JxufeTheme.primaryColor.withAlpha(26),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(100),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: JxufeTheme.primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '江西财经大学统一身份认证',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: JxufeTheme.textColor,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    'Jiangxi University of Finance and Economics',
                    style: TextStyle(fontSize: 12, color: JxufeTheme.hintColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 1,
            color: JxufeTheme.borderColor,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLoginCard(
    BuildContext context,
    LoginState state,
    LoginViewModel viewModel,
  ) {
    return Container(
      width: 450,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildFormTitle(),
            const SizedBox(height: 16),
            _buildAccountField(state, viewModel),
            const SizedBox(height: 16),
            _buildPasswordField(context, state, viewModel),
            if (state.errorMessage != null) _buildErrorMsg(state.errorMessage!),
            const SizedBox(height: 24),
            _buildLoginButton(state, viewModel, context),
            const SizedBox(height: 24),
            _buildOtherLoginIcons(context, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildFormTitle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: JxufeTheme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '账号密码登录',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: JxufeTheme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountField(LoginState state, LoginViewModel viewModel) {
    return Container(
      decoration: BoxDecoration(
        color: JxufeTheme.inputBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: (value) => viewModel.updateAccount(value),
        decoration: InputDecoration(
          hintText: '请输入校园卡号',
          hintStyle: TextStyle(color: JxufeTheme.hintColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: Icon(
            Icons.person_outline_rounded,
            color: JxufeTheme.primaryColor.withAlpha(96),
          ),
        ),
        style: TextStyle(color: JxufeTheme.textColor),
        keyboardType: TextInputType.text,
      ),
    );
  }

  Widget _buildPasswordField(
    BuildContext context,
    LoginState state,
    LoginViewModel viewModel,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: JxufeTheme.inputBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: (value) => viewModel.updatePassword(value),
        decoration: InputDecoration(
          hintText: '请输入登录密码',
          hintStyle: TextStyle(color: JxufeTheme.hintColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: JxufeTheme.primaryColor.withAlpha(96),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              state.passwordVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: JxufeTheme.hintColor,
            ),
            onPressed: viewModel.togglePasswordVisibility,
          ),
        ),
        style: TextStyle(color: JxufeTheme.textColor),
        obscureText: !state.passwordVisible,
        onSubmitted: (_) => viewModel.login(context),
      ),
    );
  }

  Widget _buildErrorMsg(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JxufeTheme.primaryColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JxufeTheme.primaryColor.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: JxufeTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: JxufeTheme.primaryColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(
    LoginState state,
    LoginViewModel viewModel,
    BuildContext context,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: state.isLoading ? null : () => viewModel.login(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: JxufeTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: state.isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Text(
                '登录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }

  Widget _buildOtherLoginIcons(BuildContext context, LoginViewModel viewModel) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildIconButton(
          icon: Icons.qr_code_rounded,
          color: JxufeTheme.primaryColor,
          onTap: () => viewModel.scanLogin(context),
        ),
        const SizedBox(width: 32),
        _buildIconButton(
          icon: Icons.wechat,
          color: const Color(0xFF14c468),
          onTap: () => viewModel.wechatLogin(context),
        ),
        const SizedBox(width: 32),
        _buildIconButton(
          icon: ExpandIcons.wecon,
          color: const Color(0xFF73A9EC),
          onTap: () => viewModel.showWecomUnavailable(context),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    // 简化版，未实现 hover 动画（可保留原始逻辑但略复杂，此处省略）
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: JxufeTheme.inputBgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: JxufeTheme.borderColor),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 40, bottom: 24),
      child: Column(
        children: [
          Container(
            height: 1,
            color: JxufeTheme.borderColor,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          const Text(
            'Copyright© 2026 All right reserved.',
            style: TextStyle(fontSize: 12, color: JxufeTheme.hintColor),
          ),
        ],
      ),
    );
  }
}
