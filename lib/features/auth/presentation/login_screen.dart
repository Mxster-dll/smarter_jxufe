import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_state.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_viewmodel.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool showBackButton;

  const LoginScreen({super.key, this.showBackButton = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _passwordFocusNode = FocusNode();

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginViewModelProvider);
    final viewModel = ref.read(loginViewModelProvider.notifier);

    ref.listen(loginViewModelProvider, (previous, next) {
      if (next.loginSuccess && !next.isLoading) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.recessed(context),
      body: Stack(
        children: [
          _buildBackgroundDecorations(context),
          SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 60),
                  _buildLoginCard(context, state, viewModel),
                  const SizedBox(height: 40),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecorations(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.tint(context, scheme.primary, 26 / 255),
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
              color: AppColors.tint(context, scheme.primary, 26 / 255),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(100),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 40),
      child: Stack(
        children: [
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      color: scheme.onPrimary,
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
                          color: AppColors.textBase(context),
                          height: 1.2,
                        ),
                      ),
                      Text(
                        'Jiangxi University of Finance and Economics',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                height: 1,
                color: AppColors.stroke(context),
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              const SizedBox(height: 24),
            ],
          ),
          // 返回按钮（仅从账户页进入时显示）
          if (widget.showBackButton)
            Positioned(
              left: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
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
        color: AppColors.card(context),
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
            _buildFormTitle(context, state.errorMessage, state.errorVersion),
            const SizedBox(height: 16),
            _buildAccountField(context, state, viewModel),
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

  Widget _buildFormTitle(
    BuildContext context,
    String? errorMessage,
    int errorVersion,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: scheme.primary,
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
                color: AppColors.textBase(context),
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
                    child: _ShakingError(
                      errorMessage,
                      errorVersion,
                      (msg) => _buildErrorMsg(context, msg),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountField(
    BuildContext context,
    LoginState state,
    LoginViewModel viewModel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: (value) => viewModel.updateAccount(value),
        onSubmitted: (_) => _passwordFocusNode.requestFocus(),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: '请输入校园卡号',
          hintStyle: TextStyle(color: AppColors.textMuted(context)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: Icon(
            Icons.person_outline_rounded,
            color: scheme.primary.withAlpha(96),
          ),
        ),
        style: TextStyle(color: AppColors.textBase(context)),
        keyboardType: TextInputType.text,
      ),
    );
  }

  Widget _buildPasswordField(
    BuildContext context,
    LoginState state,
    LoginViewModel viewModel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        focusNode: _passwordFocusNode,
        onChanged: (value) => viewModel.updatePassword(value),
        decoration: InputDecoration(
          hintText: '请输入登录密码',
          hintStyle: TextStyle(color: AppColors.textMuted(context)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: scheme.primary.withAlpha(96),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              state.passwordVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textMuted(context),
            ),
            onPressed: viewModel.togglePasswordVisibility,
          ),
        ),
        style: TextStyle(color: AppColors.textBase(context)),
        obscureText: !state.passwordVisible,
        onSubmitted: (_) => viewModel.login(context),
      ),
    );
  }

  Widget _buildErrorMsg(BuildContext context, String msg) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.tint(context, scheme.primary, 20 / 255),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.tintBorder(context, scheme.primary, 51 / 255),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: scheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            msg,
            style: TextStyle(color: scheme.primary, fontSize: 13),
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: state.isLoading ? null : () => viewModel.login(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: state.isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildOtherLoginIcon(
          Icons.qr_code_rounded,
          scheme.primary,
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
    // hover 时背景就是该入口自己的强调色 → 前景取「压在该色上」的那一档。
    // ⚠ 别用 `ThemeData.estimateBrightnessForColor`：深色主题的亮红 #F2555A
    // 会被它判成「暗底」→ 取白字只有 3.38:1，
    // 而深字有 5.16:1（实测）。`AppColors.onAccent` 按实测对比度择字。
    // 浅色下恒为白，与原先写死的 `Colors.white` 逐像素相同。
    final onColor = AppColors.onAccent(context, color);

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
                color: hovering ? color : AppColors.fill(context),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hovering ? color : AppColors.stroke(context),
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
              child: Icon(icon, color: hovering ? onColor : color, size: 24),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 40, bottom: 24),
      child: Column(
        children: [
          Container(
            height: 1,
            color: AppColors.stroke(context),
            margin: const EdgeInsets.only(bottom: 16),
          ),
          Text(
            'Copyright© 2026 All right reserved.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
          ),
        ],
      ),
    );
  }
}

class _ShakingError extends StatefulWidget {
  final String message;
  final int version;
  final Widget Function(String) builder;

  const _ShakingError(this.message, this.version, this.builder);

  @override
  State<_ShakingError> createState() => _ShakingErrorState();
}

class _ShakingErrorState extends State<_ShakingError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _shake;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shake = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(6, 0)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(6, 0), end: const Offset(-6, 0)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(-6, 0), end: const Offset(4, 0)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(4, 0), end: const Offset(-4, 0)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(-4, 0), end: Offset.zero),
        weight: 1,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _ShakingError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.version != oldWidget.version) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shake.value.dx, 0),
          child: child,
        );
      },
      child: widget.builder(widget.message),
    );
  }
}
