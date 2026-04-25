import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';

import '../../core/lyric_scroll_behavior.dart';

/// 负责歌词滚动动画控制的 Mixin
mixin LyricScrollMixin<T extends StatefulWidget>
on State<T>, TickerProviderStateMixin<T>, LyricLayoutMixin<T> {
  @override
  LyricController get controller;
  @override
  LyricStyle get style;
  @override
  Size get lyricSize;
  @override
  LyricLayout? get layout;
  ValueNotifier<double> get scrollYNotifier;

  double? get dragScrollY;
  set dragScrollY(double? value);

  late final AnimationController _scrollController;
  Animation<double>? _translationAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController = AnimationController(
      vsync: this,
      //必须解除边界限制，因为现在控制器输出的是实际坐标，而非 0.0~1.0
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
    )..addListener(() {
      final value = _translationAnimation?.value;
      if (!mounted || value == null || value == scrollY) {
        return;
      }
      scrollY = value;
    });

    controller.registerEvent(LyricEvent.reset, _reset);
    controller.activeIndexNotifiter.addListener(playIndexListener);
  }

  void _reset(_) {
    if (_scrollController.isAnimating) {
      _scrollController.stop();
    }
  }

  double get scrollY => scrollYNotifier.value;
  set scrollY(double value) {
    scrollYNotifier.value = value;
  }

  /// 播放索引变化监听
  void playIndexListener() {
    updateScrollY();
  }

  double calcActiveLineOffsetY() {
    final l = layout;
    if (l == null) {
      return 0;
    }
    final offset = l.lineOffsetY(
        controller.activeIndexNotifiter.value,
        controller.activeIndexNotifiter.value,
        l.activeAnchorPosition,
        style.activeAlignment);

    if (l.activeAnchorPosition < l.selectionAnchorPosition) {
      final lh = l.getLineHeight(true, controller.activeIndexNotifiter.value);
      final anchorOffset = l.anchorOffsetY(
          controller.activeIndexNotifiter.value,
          true,
          lh,
          style.selectionAlignment);
      final maxOffset = contentHeight -
          style.contentPadding.vertical -
          l.selectionAnchorPosition -
          (lh - anchorOffset);
      return min(offset, maxOffset);
    }
    return offset;
  }

  /// 更新偏移Y值
  void updateScrollY({bool animate = true}) {
    final currentLayout = layout;
    if (currentLayout == null) return;

    final target = dragScrollY ?? calcActiveLineOffsetY();

    if (!animate) {
      if (_scrollController.isAnimating) {
        _scrollController.stop();
      }
      scrollY = target;
      return;
    }

    if (_scrollController.isAnimating) {
      _scrollController.stop();
    }

    final offset = (scrollY - target).abs();
    if (offset < 0.1) {
      scrollY = target;
      return;
    }

    final ScrollBehaviorConfig? config = style.scrollBehavior;

    // 【修改2】兜底逻辑：如果没有配置动画行为，直接赋值跳过动画
    if (config == null) {
      scrollY = target;
      return;
    }

    _translationAnimation = config.applyAnimation(
      controller: _scrollController,
      begin: scrollY,
      end: target,
    );

    // 如果动画策略判断不需要动画（例如计算出时长为0），则直接跳到终点
    if (_translationAnimation is AlwaysStoppedAnimation) {
      scrollY = target;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    controller.unregisterEvent(LyricEvent.reset, _reset);
    controller.activeIndexNotifiter.removeListener(playIndexListener);
    super.dispose();
  }
}