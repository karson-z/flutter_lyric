import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

    // Calculate scroll delta for staggered effect
    double scrollDelta = 0.0;
    if (switchState.exitIndex != -1 && switchState.enterIndex != -1) {
       int prev = switchState.exitIndex;
       int curr = switchState.enterIndex;
       // Only apply staggered effect if index changed
       if (prev < layout.metrics.length && prev != curr) {
          // Approximate delta using previous line's height + gap
          double h = layout.getLineHeight(true, prev); 
          scrollDelta = (h + layout.style.lineGap) * (curr - prev).sign;
       }
    }

    var totalTranslateY = 0.0;
    canvas.translate(0, -scrollY);
    totalTranslateY -= scrollY;
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    // 视口内「播放行之后」的行序号，用于波浪延迟（0,1,2...），使少行时也有明显波浪
    var viewportWaveIndex = 0;
    for (var i = 0; i < layout.metrics.length; i++) {
      final isActive = i == playIndex;
      final lineHeight = layout.getLineHeight(isActive, i);

      double staggeredOffsetY = 0.0;
      //“波浪式”的歌词滚动过渡动画（延迟按视口内行序计算，保证少行时也有波浪感）
      if (style.enableWaveAnimation &&
          !isSelecting &&
          i > playIndex &&
          scrollDelta != 0.0 &&
          switchState.enterAnimationValue < 1.0) {
        double dist = viewportWaveIndex.toDouble();
        double delay = dist * 0.08;
        double t = (switchState.enterAnimationValue - delay) * 2.0;
        t = t.clamp(0.0, 1.0);
        t = Curves.easeOut.transform(t);
        staggeredOffsetY = scrollDelta * (1 - t);
      }
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
        
        if (style.activeLineOnly && !isActive) {
        } else {
          drawLine(
            canvas,
            layout.metrics[i],
            size,
            i,
            selectedIndex == i,
          );
        }
        canvas.restore();
        if (i > playIndex) viewportWaveIndex++;
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
    if (layout.style.enableScaleAnimation != true) return 0;
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
    if (index == switchState.enterIndex) {
      final enterAnimationValue = switchState.enterAnimationValue;
      final fromHeight = metric.height;
      final toHeight = metric.activeHeight;
      final transY = toHeight;
      canvas.translate(transX, transY);
      canvas.scale(
          1 - ((toHeight - fromHeight) / toHeight) * (1 - enterAnimationValue));
      canvas.translate(-transX, -transY);
    }
    // EXIT
    if (index == switchState.exitIndex) {
      final exitAnimationValue = switchState.exitAnimationValue;
      final fromHeight = metric.activeHeight;
      final toHeight = metric.height;
      final transY = 0.0;
      canvas.translate(transX, transY);
      final scale =
          ((fromHeight - toHeight) / fromHeight) * (1 - exitAnimationValue);
      canvas.scale(1 + scale);
      canvas.translate(-transX, -transY);
      return toHeight * scale;
    }
    return 0;
  }

  drawLine(
      Canvas canvas,
      LineMetrics metric,
      Size size,
      int index,
      bool isInAnchorArea,
      ) {
    final isActive = playIndex == index;

    // --- 模糊配置 ---
    const double blurSigma = 1.2;

    // --- 样式替换逻辑 ---
    TextStyle replaceTextStyle(TextStyle style, Color? selectedColor) {
      // 1. 确定最终显示颜色
      final Color targetColor = isSelecting && isInAnchorArea && selectedColor != null
          ? selectedColor
          : (style.color ?? Colors.white);

      // 2. 非激活行应用模糊
      if (!isActive) {
        return style.copyWith(
          foreground: Paint()
            ..color = targetColor
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, blurSigma),
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

    // 【状态还原】绘制完成后必须还原 TextSpan，否则会污染缓存
    painter.text = oldSpan;
    // 【建议】还原后最好也 layout 一下，确保 Painter 回到可用状态
    // 虽然下一帧会重设，但这能防止其他地方读取出错
    painter.layout(maxWidth: size.width);

    // --- 绘制高亮逻辑 ---
    if (isActive) {
      drawHighlight(canvas, size, metric.activeMetrics,
          highlightTotalWidth: metric.words?.isNotEmpty == true
              ? activeHighlightWidth
              : double.infinity);
    } else if (index == switchState.exitIndex &&
        switchState.exitAnimationValue < 1) {
      drawHighlight(canvas, size, metric.metrics,
          highlightTotalWidth: double.infinity);
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
