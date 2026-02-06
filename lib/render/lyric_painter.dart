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
    if (switchState.previousIndex != -1 && switchState.activeIndex != -1) {
       int prev = switchState.previousIndex;
       int curr = switchState.activeIndex;
       // Only apply staggered effect if index changed
       if (prev < layout.metrics.length && prev != curr) {
          // Approximate delta using previous line's height + gap
          // We assume scrolling happens to align the new line.
          // If curr > prev, we scrolled down (canvas content moves up), so lines below need to be pushed down (positive offset).
          // If curr < prev, we scrolled up, lines below need to be pushed up (negative offset).
          double h = layout.getLineHeight(true, prev); 
          scrollDelta = (h + layout.style.lineGap) * (curr - prev).sign;
       }
    }

    var totalTranslateY = 0.0;
    canvas.translate(0, -scrollY);
    totalTranslateY -= scrollY;
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    for (var i = 0; i < layout.metrics.length; i++) {
      final isActive = i == playIndex;
      final lineHeight = layout.getLineHeight(isActive, i);
      
      // STAGGERED LOGIC
      double staggeredOffsetY = 0.0;
      if (i > playIndex && scrollDelta != 0.0 && switchState.animationValue < 1.0) {
         double dist = (i - playIndex).toDouble();
         double delay = dist * 0.08; 
         double t = (switchState.animationValue - delay) * 2.0; 
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

  drawLine(
    Canvas canvas,
    LineMetrics metric,
    Size size,
    int index,
    bool isInAnchorArea,
  ) {
    final isActive = playIndex == index;
    TextStyle replaceTextStyle(TextStyle style, Color color) {
      return style.copyWith(
          color: isSelecting && isInAnchorArea ? color : style.color);
    }

    final painter = isActive ? metric.activeTextPainter : metric.textPainter;
    // 获取原来的 TextSpan
    final oldSpan = painter.text!;

    // 创建一个新的 TextSpan，只修改 color
    painter.text = TextSpan(
      text: oldSpan.toPlainText(), // 保持文字不变
      style: replaceTextStyle(
        oldSpan.style!,
        layout.style.selectedColor,
      ),
    );
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
    
    painter.paint(
      canvas,
      Offset(0, 0),
    );
    painter.text = oldSpan;
    if (isActive) {
      drawHighlight(canvas, size, metric.activeMetrics,
          highlightTotalWidth: metric.words?.isNotEmpty == true
              ? activeHighlightWidth
              : double.infinity);
    } 
    
    canvas.restore();
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
      canvas.save();
      canvas.translate(calcContentAliginOffset(tPainter.width, size.width), 0);
      
      try {
        tPainter.paint(
          canvas,
          Offset(0, mainHeight + layout.style.translationLineGap),
        );
      } catch (_) {
        // 避免系统字体变更触发 assert(debugSize == size);
      }
      tPainter.text = tOldSpan;
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
