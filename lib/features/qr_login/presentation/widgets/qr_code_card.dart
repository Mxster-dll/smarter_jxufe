import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_display_strategies.dart';

/// QR码卡片——纯UI组件，通过 Riverpod 获取状态
class QrCodeCard extends ConsumerWidget {
  const QrCodeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qrLoginViewModelProvider);
    final viewModel = ref.read(qrLoginViewModelProvider.notifier);
    const double sideLength = 200;

    final strategy = QrCodeDisplayStrategyFactory.createStrategy(state.status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JxufeTheme.borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: sideLength, minHeight: sideLength),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
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
            if (state.status.isFinal) const SizedBox(height: 12),
            if (state.status.isFinal)
              OutlinedButton(
                onPressed: () => viewModel.refresh(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: JxufeTheme.secondaryColor, width: 1),
                ),
                child: const Text(
                  '刷新',
                  style: TextStyle(color: JxufeTheme.secondaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
