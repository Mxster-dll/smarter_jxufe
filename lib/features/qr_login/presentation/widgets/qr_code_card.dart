import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_display_strategies.dart';

/// QR码卡片——纯UI组件，通过 Riverpod 获取状态
class QrCodeCard extends ConsumerWidget {
  /// 是否显示外层边框容器。在 [UnifiedMfaDialog] 等已自带外壳的场景下设为 false。
  final bool showOuterDecoration;

  /// 是否显示内部刷新按钮。在 [UnifiedMfaDialog] 等已将刷新按钮浮于外层容器时设为 false。
  final bool showRefreshButton;

  /// 是否显示底部提示文字。
  final bool showHint;
  const QrCodeCard({
    super.key,
    this.showOuterDecoration = true,
    this.showRefreshButton = true,
    this.showHint = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qrLoginViewModelProvider);
    final viewModel = ref.read(qrLoginViewModelProvider.notifier);
    const double sideLength = 200;

    final strategy = QrCodeDisplayStrategyFactory.createStrategy(state.status);

    final innerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: sideLength,
            minHeight: sideLength,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // top row: refresh button aligned right
              if (showRefreshButton)
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      onPressed: () => viewModel.refresh(),
                      tooltip: '刷新',
                      hoverColor: JxufeTheme.secondaryColor.withAlpha(40),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: JxufeTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(36),
                child: SizedBox(
                  width: sideLength,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(state.status),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          if (state.qrImage != null && !state.isLoading)
                            ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: state.isPending ? 0 : 5,
                                sigmaY: state.isPending ? 0 : 5,
                              ),
                              child: Opacity(
                                opacity: state.isPending ? 1 : 0.5,
                                child: Image.memory(
                                  state.qrImage!,
                                  height: sideLength,
                                  width: sideLength,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: sideLength,
                              minHeight: sideLength,
                            ),
                            child: Center(
                              widthFactor: 1,
                              heightFactor: 1,
                              child: strategy.buildWidget(context, state),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showHint)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '使用 ',
                          style: TextStyle(
                            fontSize: 13,
                            color: JxufeTheme.hintColor,
                          ),
                        ),
                        const TextSpan(
                          text: '微信',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF14c468),
                          ),
                        ),
                        const TextSpan(
                          text: ' 或 ',
                          style: TextStyle(
                            fontSize: 13,
                            color: JxufeTheme.hintColor,
                          ),
                        ),
                        const TextSpan(
                          text: '企业微信',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF73A9EC),
                          ),
                        ),
                        const TextSpan(
                          text: ' 扫码以完成验证',
                          style: TextStyle(
                            fontSize: 13,
                            color: JxufeTheme.hintColor,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (!showOuterDecoration) return innerContent;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JxufeTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: innerContent,
    );
  }
}
