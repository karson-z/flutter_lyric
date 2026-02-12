import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_line_view_model.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';

const _debugLyric = false;

class LyricPainter extends CustomPainter {
  final LyricLayout layout;
  final int playIndex;
  final double scrollY;
  final double activeHighlightWidth;
  final LyricLineSwitchState switchState;
  final bool isSelecting;
  final LyricStyle style;
  final Function(
    int,
  ) onAnchorIndexChange;
  final Function(
    Map<int, Rect>,
  ) onShowLineRectsChange;
  
  // 新增：接收 ViewModels
  final List<LyricLineViewModel>? viewModels;

  LyricPainter({
    required this.layout,
    required this.playIndex,
    required this.scrollY,
    required this.onAnchorIndexChange,
    required this.activeHighlightWidth,
    required this.switchState,
    required this.isSelecting,
    required this.onShowLineRectsChange,
    required this.style,
    this.viewModels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    //溢出裁剪
    if (!_debugLyric) {
      canvas.clipRect(Rect.fromLTRB(-layout.style.contentPadding.left, 0,
          size.width + layout.style.contentPadding.right, size.height));
    }

    final selectionPosition = layout.selectionAnchorPosition;
    final activePosition = layout.activeAnchorPosition;
    if (_debugLyric) {
      canvas.drawLine(
        Offset(0, selectionPosition),
        Offset(size.width, selectionPosition),
        Paint()..color = layout.style.selectedColor,
      );
      canvas.drawLine(
        Offset(0, activePosition),
        Offset(size.width, activePosition),
        Paint()..color = layout.style.selectedColor,
      );
    }
    var totalTranslateY = 0.0;
    canvas.translate(0, -scrollY);
    totalTranslateY -= scrollY;
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    for (var i = 0; i < layout.metrics.length; i++) {
      final isActive = i == playIndex;
      final lineHeight = layout.getLineHeight(isActive, i);

      double staggeredOffsetY = 0.0;
      totalTranslateY += lineHeight;
      //计算高亮
      if ((totalTranslateY + layout.style.lineGap / 2) >= selectionPosition &&
          selectedIndex == -1) {
        selectedIndex = i;
        onAnchorIndexChange(
          i,
        );
      }
      if (totalTranslateY - lineHeight >= size.height) {
        break;
      }
      if (totalTranslateY > 0) {
        final lineRect = Rect.fromLTWH(0, totalTranslateY - lineHeight,
            size.width + layout.style.contentPadding.horizontal, lineHeight);
        showLineRects[i] = lineRect;

        // Apply staggered offset
      canvas.save();
      canvas.translate(0, staggeredOffsetY);

      // --- Apple Music Style Animation ---
      if (viewModels != null && i < viewModels!.length) {
        final vm = viewModels![i];
        
        // 1. Scale
        // 根据对齐方式确定缩放中心点
        double originX = 0;
        if (layout.style.contentAlignment == CrossAxisAlignment.center) {
          originX = size.width / 2;
        } else if (layout.style.contentAlignment == CrossAxisAlignment.end) {
          originX = size.width;
        }
        // Start 默认为 0
        
        final centerY = lineHeight / 2;
        
        // 应用缩放
        canvas.translate(originX, centerY);
        canvas.scale(vm.currentScale);
        canvas.translate(-originX, -centerY);
        
        // 注意：透明度和模糊在 drawLine 内部处理，这里我们传递额外参数或在 drawLine 里访问 vm?
        // 由于 drawLine 内部逻辑较深，我们直接修改 metric 里的 painter 属性不太好
        // 我们可以通过 saveLayer 来应用透明度
        if (vm.currentOpacity < 1.0) {
           // 简单的透明度应用 (注意这可能会影响性能，但在 CustomPainter 中是标准做法)
           // 如果不使用 saveLayer，可以直接修改 Paint 的 color alpha，但需要深入 drawLine
        }
      }

      if (style.activeLineOnly && !isActive) {
      } else {
        drawLine(
          canvas,
          layout.metrics[i],
          size,
          i,
          selectedIndex == i,
          viewModels != null && i < viewModels!.length ? viewModels![i] : null, // Pass VM
        );
      }
      canvas.restore();
      }
      totalTranslateY += layout.style.lineGap;
      if (_debugLyric) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, lineHeight),
            Paint()..color = Colors.purple.withAlpha(50));
      }
      canvas.translate(0, lineHeight + layout.style.lineGap);
    }
    onShowLineRectsChange(showLineRects);
  }

  drawHighlight(
    Canvas canvas,
    Size size,
    List<ui.LineMetrics> metrics, {
    double highlightTotalWidth = 0,
  }) {
    if (highlightTotalWidth < 0) return;
    final activeHighlightColor = layout.style.activeHighlightColor;
    final activeHighlightGradient = layout.style.activeHighlightGradient;
    if (activeHighlightColor == null && activeHighlightGradient == null) {
      return;
    }

    final highlightFullMode = highlightTotalWidth == double.infinity;
    var accWidth = 0.0;

    final Paint paint = Paint()..blendMode = BlendMode.srcIn;

    for (var line in metrics) {
      double lineDrawWidth;
      bool isFullLine;

      if (highlightFullMode) {
        isFullLine = true;
        lineDrawWidth = line.width;
      } else {
        final remain = highlightTotalWidth - accWidth;
        if (remain <= 0) break;

        lineDrawWidth = remain < line.width ? remain : line.width;
        isFullLine = remain >= line.width;
      }

      final top = line.baseline - line.ascent;
      final height = (line.ascent + line.descent);

      final extraFadeWidth = style.activeHighlightExtraFadeWidth;
      final pad = 2;
      final rect = Rect.fromLTWH(
        line.left - pad,
        top,
        lineDrawWidth + pad,
        height,
      );

      final grad = style.activeHighlightGradient ??
          LinearGradient(colors: [activeHighlightColor!, activeHighlightColor]);
      handleExtraFadeWidth() {
        if (extraFadeWidth <= 0) return 0;
        paint.shader = LinearGradient(colors: [
          grad.colors.last,
          style.activeStyle.color ?? grad.colors.last
        ]).createShader(Rect.fromLTWH(
            rect.left + rect.width, rect.top, extraFadeWidth, rect.height));
        canvas.drawRect(
            Rect.fromLTWH(
                rect.left + rect.width, rect.top, extraFadeWidth, rect.height),
            paint);
      }

      handleExtraFadeWidth();
      paint.shader = grad.createShader(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height));
      canvas.drawRect(rect, paint);
      accWidth += line.width;

      if (!isFullLine) break;
    }
  }

  double handleSwitchAnimation(
      Canvas canvas,
      LineMetrics metric,
      int index,
      LyricLineSwitchState switchState,
      TextPainter painter,
      Size size,
      ) {
    if (layout.style.enableSwitchAnimation != true) return 0;

    // 计算水平中心点 (保持你原有的逻辑)
    double calcTranslateX(double contentWidth) {
      var transX = 0.0;
      if (layout.style.contentAlignment == CrossAxisAlignment.center) {
        transX = contentWidth / 2;
      } else if (layout.style.contentAlignment == CrossAxisAlignment.end) {
        transX = contentWidth;
      }
      return transX;
    }

    final transX = calcTranslateX(painter.width);

    // 定义一个缓动曲线，让缩放不那么生硬
    // 如果你的 AnimationValue 已经是物理弹簧产生的，这里可以用 Curves.linear
    // 如果觉得弹簧不够软，可以用 Curves.easeOutQuart 增加一点细腻的减速感
    const curve = Curves.linear;

    // --- ENTER (从小变大) ---
    if (index == switchState.enterIndex) {
      // 应用曲线
      final t = curve.transform(switchState.enterAnimationValue); // 0.0 -> 1.0

      final activeH = metric.activeHeight;
      final normalH = metric.height;

      final targetScale = ui.lerpDouble(normalH / activeH, 1.0, t)!;

      // 【关键优化】缩放中心点设为高度的一半 (垂直居中)
      // 因为 activeTextPainter 的高度是 activeH
      final transY = activeH / 2.0;

      canvas.translate(transX, transY);
      canvas.scale(targetScale);
      canvas.translate(-transX, -transY);
    }

    // --- EXIT (从大变小) ---
    if (index == switchState.exitIndex) {
      // 应用曲线 (注意 exit 是 1.0 -> 0.0)
      // 我们希望动画进程是 0.0(刚开始退) -> 1.0(退完了)
      final t = curve.transform(1.0 - switchState.exitAnimationValue);

      final activeH = metric.activeHeight;
      final normalH = metric.height;

      final targetScale = ui.lerpDouble(activeH / normalH, 1.0, t)!;
      final transY = normalH / 2.0;

      canvas.translate(transX, transY);
      canvas.scale(targetScale);
      canvas.translate(-transX, -transY);

      return 0;
    }

    return 0;
  }

  drawLine(
      Canvas canvas,
      LineMetrics metric,
      Size size,
      int index,
      bool isInAnchorArea, [
      LyricLineViewModel? vm,
  ]) {
    final isActive = playIndex == index;

    // --- 模糊配置 ---
    // 如果有 VM，使用 VM 的 blur，否则使用默认逻辑
    double blurSigma = vm?.currentBlur ?? 1.2;

    // --- 样式替换逻辑 ---
    TextStyle replaceTextStyle(TextStyle style, Color? selectedColor) {
      // 1. 确定最终显示颜色
      Color targetColor = isSelecting && isInAnchorArea && selectedColor != null
          ? selectedColor
          : (style.color ?? Colors.white);
          
      // 应用 VM 的透明度
      if (vm != null) {
        targetColor = targetColor.withOpacity(
          (targetColor.opacity * vm.currentOpacity).clamp(0.0, 1.0)
        );
      }

      // 2. 非激活行应用模糊，或者 VM 指定了模糊
      if (!isActive || (vm != null && vm.currentBlur > 0)) {
        return style.copyWith(
          foreground: Paint()
            ..color = targetColor
            ..maskFilter = blurSigma > 0 ? MaskFilter.blur(BlurStyle.normal, blurSigma) : null,
        );
      }

      // 3. 激活行仅处理选中变色
      return style.copyWith(color: targetColor);
    }

    final painter = isActive ? metric.activeTextPainter : metric.textPainter;
    // 保存原始 TextSpan
    final oldSpan = painter.text!;

    // 应用新样式
    painter.text = TextSpan(
      text: oldSpan.toPlainText(),
      style: replaceTextStyle(
        oldSpan.style!,
        layout.style.selectedColor,
      ),
    );

    // 【关键修复】修改 text 后必须重新 layout，否则无法获取 width 或 paint
    painter.layout(maxWidth: size.width);

    canvas.save();
    // 现在可以安全访问 painter.width 了
    canvas.translate(calcContentAliginOffset(painter.width, size.width), 0);

    if (_debugLyric) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, painter.width, painter.height),
          Paint()
            ..color = !isActive
                ? Colors.blue.withAlpha(50)
                : Colors.red.withAlpha(50));
    }

    // 处理行切换动画
    final switchOffset = handleSwitchAnimation(
        canvas, metric, index, switchState, painter, size);

    // 绘制文字
    painter.paint(
      canvas,
      const Offset(0, 0),
    );

    // 【状态还原】
    painter.text = oldSpan;
    painter.layout(maxWidth: size.width);

    // --- 绘制高亮逻辑 (修复版) ---
    if (isActive) {
      // 1. 当前激活行：绘制卡拉OK逐字高亮
      drawHighlight(canvas, size, metric.activeMetrics,
          highlightTotalWidth: metric.words?.isNotEmpty == true
              ? activeHighlightWidth
              : double.infinity); // 如果没时间轴，默认全高亮

    } else if (index == switchState.exitIndex) {
      final double fadeOpacity = switchState.exitAnimationValue.clamp(0.0, 1.0);

      if (fadeOpacity > 0.01) {
        canvas.saveLayer(
            Rect.fromLTWH(0, 0, painter.width, painter.height),
            Paint()..color = Colors.white.withOpacity(fadeOpacity)
        );
        drawHighlight(canvas, size, metric.metrics,
            highlightTotalWidth: double.infinity);
        canvas.restore();
      }
    }

    canvas.restore();

    // --- 处理翻译行 ---
    final mainHeight = isActive ? metric.activeHeight : metric.height;
    if (metric.line.translation?.isNotEmpty == true) {
      final tPainter = metric.translationTextPainter;
      final tOldSpan = tPainter.text;

      tPainter.text = TextSpan(
        text: metric.line.translation,
        style: replaceTextStyle(
          tPainter.text!.style!.copyWith(
              color: isActive ? layout.style.translationActiveColor : null),
          layout.style.selectedTranslationColor,
        ),
      );

      // 【关键修复】翻译行修改后也需要 layout
      tPainter.layout(maxWidth: size.width);

      canvas.save();
      canvas.translate(calcContentAliginOffset(tPainter.width, size.width), 0);
      canvas.translate(0, switchOffset);

      try {
        tPainter.paint(
          canvas,
          Offset(0, mainHeight + layout.style.translationLineGap),
        );
      } catch (_) {}

      // 还原翻译行
      tPainter.text = tOldSpan;
      tPainter.layout(maxWidth: size.width); // 还原 layout

      canvas.translate(0, -switchOffset);
      canvas.restore();
    }
  }

  double calcContentAliginOffset(double contentWidth, double containerWidth) {
    switch (layout.style.contentAlignment) {
      case CrossAxisAlignment.start:
        return 0;
      case CrossAxisAlignment.end:
        return containerWidth - contentWidth;
      case CrossAxisAlignment.center:
        return (containerWidth - contentWidth) / 2;
      default:
        return 0;
    }
  }

  @override
  bool shouldRepaint(covariant LyricPainter oldDelegate) {
    final shouldRepaint = layout != oldDelegate.layout ||
        playIndex != oldDelegate.playIndex ||
        scrollY != oldDelegate.scrollY ||
        activeHighlightWidth != oldDelegate.activeHighlightWidth ||
        switchState != oldDelegate.switchState;
    return shouldRepaint;
  }
}
