import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // 需要引入 Scheduler 来使用 Ticker
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';

import '../../core/lyric_spring.dart';

// 【注意】这里假设上面的 Spring 代码保存在 'spring_engine.dart' 中
// import 'spring_engine.dart';

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

  // --- 替换部分开始 ---

  // 1. 自定义物理引擎实例
  late final Spring _spring;

  // 2. 驱动器
  late final Ticker _ticker;

  // 3. 记录上一帧时间，用于计算 delta
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();

    // 初始化物理引擎
    _spring = Spring(initialPosition: 0);
    // 配置物理参数 (可以从 style 中读取，或者写死)
    _spring.updateParams(const SpringOptions(
      mass: 1.0,
      stiffness: 100.0,
      damping: 20.0, // 20.0 比较稳，想Q弹就改小，比如 10
      soft: false,
    ));

    // 初始化 Ticker
    _ticker = createTicker((elapsed) {
      // 计算两帧之间的时间差 (秒)
      final double delta = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;

      // 更新物理状态
      _spring.update(delta);

      // 更新 ScrollY
      final currentPos = _spring.getCurrentPosition();

      // 只有数值变化才通知 UI 更新，节省性能
      if ((scrollY - currentPos).abs() > 0.001) {
        scrollY = currentPos;
      }

      // 物理静止检测：如果到达目标且速度为0，暂停 Ticker 省电
      if (_spring.arrived()) {
        _ticker.stop();
        // 强制对齐最后一次位置
        if (scrollY != _spring.getCurrentPosition()) {
          scrollY = _spring.getCurrentPosition();
        }
      }
    });

    controller.registerEvent(LyricEvent.reset, _reset);
    controller.activeIndexNotifiter.addListener(playIndexListener);
  }

  void _reset(_) {
    _ticker.stop();
    _spring.setPosition(0);
    scrollY = 0;
  }

  double get scrollY => scrollYNotifier.value;
  set scrollY(double value) {
    scrollYNotifier.value = value;
  }

  void playIndexListener() {
    updateScrollY();
  }

  // 计算偏移量的逻辑保持不变
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
    if (currentLayout != null) {
      final target = dragScrollY ?? calcActiveLineOffsetY();

      // 如果没有动画，直接瞬移
      if (!animate) {
        if (_ticker.isActive) _ticker.stop();
        _spring.setPosition(target);
        scrollY = target;
        return;
      }

      // 如果目标没有变，且已经静止，就不做操作
      // (这里不需要像 AnimationController 那样判断 isAnimating，
      // 因为 setTargetPosition 会自动处理 velocity 继承)

      // 设置新目标：Spring 内部会自动处理“还没停稳就去新地方”的速度继承
      _spring.setTargetPosition(target);

      // 启动 Ticker 循环
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero; // 重置时间差
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    controller.unregisterEvent(LyricEvent.reset, _reset);
    controller.activeIndexNotifiter.removeListener(playIndexListener);
    super.dispose();
  }
}