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
    final layoutStyle = layout.style;
    final lineGap = layoutStyle.lineGap;
    final metrics = layout.metrics;

    if (!_debugLyric) {
      canvas.clipRect(Rect.fromLTRB(-layoutStyle.contentPadding.left, 0,
          size.width + layoutStyle.contentPadding.right, size.height));
    }

    final selectionPosition = layout.selectionAnchorPosition;
    if (_debugLyric) {
      final activePosition = layout.activeAnchorPosition;
      final debugPaint = Paint()..color = layoutStyle.selectedColor;
      canvas.drawLine(
        Offset(0, selectionPosition),
        Offset(size.width, selectionPosition),
        debugPaint,
      );
      canvas.drawLine(
        Offset(0, activePosition),
        Offset(size.width, activePosition),
        debugPaint,
      );
    }
    var totalTranslateY = -scrollY;
    canvas.translate(0, -scrollY);
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    final halfLineGap = lineGap / 2;
    final contentHorizontal = layoutStyle.contentPadding.horizontal;
    final activeLineOnly = style.activeLineOnly;

    for (var i = 0; i < metrics.length; i++) {
      final isActive = i == playIndex;
      final lineHeight = layout.getLineHeight(isActive, i);
      totalTranslateY += lineHeight;
      if ((totalTranslateY + halfLineGap) >= selectionPosition &&
          selectedIndex == -1) {
        selectedIndex = i;
        onAnchorIndexChange(i);
      }
      if (totalTranslateY - lineHeight >= size.height) {
        break;
      }
      if (totalTranslateY > 0) {
        showLineRects[i] = Rect.fromLTWH(0, totalTranslateY - lineHeight,
            size.width + contentHorizontal, lineHeight);
        if (!activeLineOnly || isActive) {
          drawLine(canvas, metrics[i], size, i, selectedIndex == i);
        }
      }
      totalTranslateY += lineGap;
      if (_debugLyric) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, lineHeight),
            Paint()..color = Colors.purple.withAlpha(50));
      }
      canvas.translate(0, lineHeight + lineGap);
    }
    onShowLineRectsChange(showLineRects);
  }

  drawHighlight(
    Canvas canvas,
    Size size,
    List<ui.LineMetrics> metrics, {
    double highlightTotalWidth = 0,
    double animationOpacity = 1.0,
  }) {
    if (highlightTotalWidth < 0 || animationOpacity <= 0) return;
    final activeHighlightColor = layout.style.activeHighlightColor;
    final activeHighlightGradient = layout.style.activeHighlightGradient;
    if (activeHighlightColor == null && activeHighlightGradient == null) {
      return;
    }

    final highlightFullMode = highlightTotalWidth == double.infinity;
    var accWidth = 0.0;

    final Paint paint = Paint()
      ..blendMode =
          animationOpacity < 1.0 ? BlendMode.srcATop : BlendMode.srcIn;

    final grad = activeHighlightGradient ??
        LinearGradient(colors: [activeHighlightColor!, activeHighlightColor]);

    final opColors = animationOpacity < 1.0
        ? grad.colors
            .map((c) =>
                c.withValues(alpha: (c.a * animationOpacity).clamp(0.0, 1.0)))
            .toList()
        : grad.colors;

    final extraFadeWidth = style.activeHighlightExtraFadeWidth;
    Color? fadeEndColor;
    if (extraFadeWidth > 0) {
      final baseEndColor = style.activeStyle.color ?? grad.colors.last;
      fadeEndColor = baseEndColor.withValues(
          alpha: (baseEndColor.a * animationOpacity).clamp(0.0, 1.0));
    }

    const pad = 2;

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
      final height = line.ascent + line.descent;

      final rect = Rect.fromLTWH(
        line.left - pad,
        top,
        lineDrawWidth + pad,
        height,
      );

      if (extraFadeWidth > 0) {
        final fadeRect = Rect.fromLTWH(
            rect.left + rect.width, rect.top, extraFadeWidth, rect.height);
        paint.shader = LinearGradient(colors: [opColors.last, fadeEndColor!])
            .createShader(fadeRect);
        canvas.drawRect(fadeRect, paint);
      }

      paint.shader = LinearGradient(
        colors: opColors,
        stops: grad.stops,
        begin: grad.begin,
        end: grad.end,
        tileMode: grad.tileMode,
        transform: grad.transform,
      ).createShader(rect);
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

    //获取字号
    final normalFontSize = layout.style.textStyle.fontSize ?? 16.0;
    final activeFontSize = layout.style.activeStyle.fontSize ?? 18.0;

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

    // ENTER: 绘制的是大字 (activeTextPainter)，需要从小缩放到大
    if (index == switchState.enterIndex) {
      final enterAnimationValue = switchState.enterAnimationValue;
      final transY = metric.activeHeight;

      canvas.translate(transX, transY);
      // 使用字号比例：例如 16 / 24 = 0.66
      final startScale = normalFontSize / activeFontSize;
      // 从 startScale 平滑过渡到 1.0
      final currentScale = startScale + (1.0 - startScale) * enterAnimationValue;
      canvas.scale(currentScale);
      canvas.translate(-transX, -transY);
    }

    // EXIT: 绘制的是小字 (textPainter)，需要从大缩放到小
    if (index == switchState.exitIndex) {
      final exitAnimationValue = switchState.exitAnimationValue;
      final transY = 0.0;

      canvas.translate(transX, transY);
      // 使用字号逆比例：例如 24 / 16 = 1.5
      final startScale = activeFontSize / normalFontSize;
      // 从 startScale 平滑缩小到 1.0
      final currentScale = 1.0 + (startScale - 1.0) * (1.0 - exitAnimationValue);
      canvas.scale(currentScale);
      canvas.translate(-transX, -transY);

      // 返回 Y 轴补偿偏移，防止因为缩小导致下方的行产生间隙
      return metric.height * (currentScale - 1.0);
    }
    return 0;
  }
  Color _resolveColor(TextStyle baseStyle, Color selectColor, bool isSelecting,
      bool isInAnchorArea, Color? customColor) {
    if (isSelecting && isInAnchorArea) return selectColor;
    return customColor ?? baseStyle.color!;
  }

  drawLine(
      Canvas canvas,
      LineMetrics metric,
      Size size,
      int index,
      bool isInAnchorArea,
      ) {
    final isActive = playIndex == index;
    final layoutStyle = layout.style;

    final painter = isActive ? metric.activeTextPainter : metric.textPainter;
    final oldSpan = painter.text! as TextSpan;

    double highlightOpacity = 1.0;
    Color? animatedMainColor;

    // 仅主歌词参与颜色切换动画
    if (style.enableSwitchAnimation) {
      final normalColor = layoutStyle.textStyle.color;
      final activeColor = layoutStyle.activeStyle.color;

      if (index == switchState.enterIndex) {
        animatedMainColor = Color.lerp(
            normalColor, activeColor, switchState.enterAnimationValue);
        highlightOpacity = switchState.enterAnimationValue;
      } else if (index == switchState.exitIndex) {
        animatedMainColor = Color.lerp(
            activeColor, normalColor, switchState.exitAnimationValue);
        highlightOpacity = 1.0 - switchState.exitAnimationValue;
      }
    }

    final targetColor = _resolveColor(oldSpan.style!, layoutStyle.selectedColor,
        isSelecting, isInAnchorArea, animatedMainColor);
    final needsRestyle = targetColor != oldSpan.style!.color;

    if (needsRestyle) {
      painter.text = TextSpan(
        text: oldSpan.text,
        style: oldSpan.style!.copyWith(color: targetColor),
      );
    }
    canvas.save();
    canvas.translate(calcContentAliginOffset(painter.width, size.width), 0);
    if (_debugLyric) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, painter.width, painter.height),
          Paint()
            ..color = !isActive
                ? Colors.blue.withAlpha(50)
                : Colors.red.withAlpha(50));
    }

    // 执行基于字号的缩放
    final switchOffset = handleSwitchAnimation(
        canvas, metric, index, switchState, painter, size);
    painter.paint(canvas, Offset.zero);

    if (needsRestyle) {
      painter.text = oldSpan;
    }

    if (isActive) {
      drawHighlight(canvas, size, metric.activeMetrics,
          highlightTotalWidth: metric.words?.isNotEmpty == true
              ? activeHighlightWidth
              : double.infinity,
          animationOpacity: highlightOpacity);
    } else if (index == switchState.exitIndex &&
        switchState.exitAnimationValue < 1 &&
        style.enableSwitchAnimation) {
      drawHighlight(canvas, size, metric.metrics,
          highlightTotalWidth: double.infinity,
          animationOpacity: highlightOpacity);
    }
    canvas.restore();

    // =============== 翻译行绘制（无动画版本） ===============
    if (metric.line.translation?.isNotEmpty == true) {
      final tPainter = metric.translationTextPainter;
      final tOldSpan = tPainter.text! as TextSpan;

      // 翻译行直接使用状态色，不参与任何 lerp 动画
      final tBaseColor = isActive
          ? (layoutStyle.translationActiveColor ?? tOldSpan.style!.color)
          : tOldSpan.style!.color;

      final tTargetColor = _resolveColor(
          tOldSpan.style!.copyWith(color: tBaseColor),
          layoutStyle.selectedTranslationColor,
          isSelecting,
          isInAnchorArea,
          null); // 无动画颜色

      final tNeedsRestyle = tTargetColor != tOldSpan.style!.color;

      if (tNeedsRestyle) {
        tPainter.text = TextSpan(
          text: tOldSpan.text,
          style: tOldSpan.style!.copyWith(color: tTargetColor),
        );
      }

      canvas.save();
      canvas.translate(calcContentAliginOffset(tPainter.width, size.width), 0);

      // 保留 switchOffset 用于 Y 轴布局补偿
      canvas.translate(0, switchOffset);
      try {
        final mainHeight = isActive ? metric.activeHeight : metric.height;
        tPainter.paint(
          canvas,
          Offset(0, mainHeight + layoutStyle.translationLineGap),
        );
      } catch (_) {}

      if (tNeedsRestyle) {
        tPainter.text = tOldSpan;
      }
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
