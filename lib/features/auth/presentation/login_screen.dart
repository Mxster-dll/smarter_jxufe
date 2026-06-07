import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_state.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loginViewModelProvider);
    final viewModel = ref.read(loginViewModelProvider.notifier);

    ref.listen(loginViewModelProvider, (previous, next) {
      if (next.loginSuccess && !next.isLoading) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ImsSplashScreen()),
        );
      }
    });

    return Scaffold(
      backgroundColor: JxufeTheme.backgroundColor,
      body: Stack(
        children: [
          _buildBackgroundDecorations(),
          SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 60),
                  _buildLoginCard(context, state, viewModel),
                  const SizedBox(height: 40),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormTitle(state.errorMessage),
            const SizedBox(height: 16),
            _buildAccountField(state, viewModel),
            const SizedBox(height: 16),
            _buildPasswordField(context, state, viewModel),
            const SizedBox(height: 24),
            _buildLoginButton(state, viewModel, context),
            const SizedBox(height: 24),
            _buildOtherLoginIcons(context, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildFormTitle(String? errorMessage) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '账号密码登录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: JxufeTheme.textColor,
              ),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0.3, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            child: errorMessage != null
                ? ConstrainedBox(
                    key: const ValueKey('error'),
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: _buildErrorMsg(errorMessage),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: JxufeTheme.primaryColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JxufeTheme.primaryColor.withAlpha(51)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: JxufeTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            msg,
            style: TextStyle(color: JxufeTheme.primaryColor, fontSize: 13),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
        _buildOtherLoginIcon(
          Icons.qr_code_rounded,
          JxufeTheme.primaryColor,
          onTap: () => viewModel.scanLogin(context),
        ),
        const SizedBox(width: 32),
        _buildOtherLoginIcon(
          Icons.wechat,
          const Color(0xFF14c468),
          onTap: () => viewModel.wechatLogin(context),
        ),
        const SizedBox(width: 32),
        _buildOtherLoginIcon(
          ExpandIcons.wecon,
          const Color(0xFF73A9EC),
          onTap: () => viewModel.showWecomUnavailable(context),
        ),
      ],
    );
  }

  Widget _buildOtherLoginIcon(
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) {
    final isHovering = ValueNotifier<bool>(false);

    return MouseRegion(
      onEnter: (_) => isHovering.value = true,
      onExit: (_) => isHovering.value = false,
      child: GestureDetector(
        onTap: onTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: isHovering,
          builder: (context, hovering, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hovering ? color : JxufeTheme.inputBgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hovering ? color : JxufeTheme.borderColor,
                  width: hovering ? 2 : 1,
                ),
                boxShadow: hovering
                    ? [
                        BoxShadow(
                          color: color.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: hovering ? Colors.white : color,
                size: 24,
              ),
            );
          },
        ),
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
