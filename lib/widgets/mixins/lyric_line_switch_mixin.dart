import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // 引入 Scheduler 以使用 Ticker
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';

import '../../core/lyric_spring.dart';


class LyricLineSwitchState {
  double exitAnimationValue = 0.0;
  double enterAnimationValue = 1.0;
  int exitIndex = -1;
  int enterIndex = -1;

  LyricLineSwitchState({
    required this.exitAnimationValue,
    required this.enterAnimationValue,
    required this.exitIndex,
    required this.enterIndex,
  });
}

mixin LyricLineSwitchMixin<T extends StatefulWidget>
on State<T>, LyricLayoutMixin<T>, TickerProviderStateMixin<T> {
  int _exitIndex = -1;
  int _enterIndex = -1;

  // --- 1. 使用物理引擎替代 AnimationController ---
  late final Spring _enterSpring;
  late final Spring _exitSpring;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    controller.registerEvent(
        LyricEvent.playSwitchAnimation, onPlaySwitchAnimation);
    controller.registerEvent(LyricEvent.reset, _reset);

    // ... 物理参数初始化保持不变 ...
    _enterSpring = Spring(initialPosition: 0);
    _enterSpring.updateParams(const SpringOptions(
      mass: 1.0, stiffness: 120.0, damping: 18.0, soft: false,
    ));

    _exitSpring = Spring(initialPosition: 1);
    _exitSpring.updateParams(const SpringOptions(
      mass: 1.0, stiffness: 150.0, damping: 20.0, soft: true,
    ));

    // --- 修改 Ticker 逻辑 ---
    _ticker = createTicker((elapsed) {
      if (_lastElapsed == Duration.zero) {
        _lastElapsed = elapsed;
        return;
      }
      final double delta = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;

      _enterSpring.update(delta);
      _exitSpring.update(delta);

      // 1. 如果两个弹簧都静止了
      if (_enterSpring.arrived() && _exitSpring.arrived()) {
        _ticker.stop();


        // 1. 将旧行的 index 移除，告诉 Painter 已经没有“正在退出”的行了
        _exitIndex = -1;

        // 2. 强制数值归位 (防止物理计算残留 0.0001 这种微小数值)
        _exitSpring.setPosition(0.0);
        _enterSpring.setPosition(1.0);

        // 3. 最后再刷新一次 UI，确保画面干净
        setState(() {});
      } else {
        // 动画进行中，正常刷新
        setState(() {});
      }
    });

    _enterIndex = _exitIndex;
    controller.activeIndexNotifiter.addListener(onActiveIndexChange);
  }

  _reset(_) {
    _ticker.stop();
    _exitIndex = -1;
    _enterIndex = -1;

    // 重置物理状态
    _exitSpring.setPosition(1.0);
    _enterSpring.setPosition(1.0); // 重置时假设所有状态归位

    setState(() {});
  }

  void onPlaySwitchAnimation(_) {
    // 强制播放一次切换动画
    if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
    _exitSpring.setPosition(0);     // 瞬间设为0
    _exitSpring.setTargetPosition(1); // 目标设为1

    _enterSpring.setPosition(0);
    _enterSpring.setTargetPosition(1);
  }

  buildLineSwitch(
      Widget Function(BuildContext context, LyricLineSwitchState state)
      builder) {
    // 物理引擎直接驱动数值，不需要 CurvedAnimation
    // 我们直接将 Spring 的 currentPosition 传给 State
    return builder(
      context,
      LyricLineSwitchState(
        // exitValue: 从 1.0 (显示) -> 0.0 (消失/变普通)
        // 注意：物理引擎这里我们配置逻辑。
        // 下面 onActiveIndexChange 里设定了 exit 目标是 0
        exitAnimationValue: _exitSpring.getCurrentPosition().clamp(0.0, 1.0),

        // enterValue: 从 0.0 (普通) -> 1.0 (高亮)
        enterAnimationValue: _enterSpring.getCurrentPosition().clamp(0.0, 1.0),

        exitIndex: _exitIndex,
        enterIndex: _enterIndex,
      ),
    );
  }

  onActiveIndexChange() {
    _exitIndex = _enterIndex;
    final old = _enterIndex;
    _enterIndex = controller.activeIndexNotifiter.value;

    if (_enterIndex != _exitIndex && old != -1) {
      // 1. 设置退出行的物理目标
      // 退出行：当前状态是 1.0 (它是旧的主角)，目标是 0.0 (变成配角)
      _exitSpring.setPosition(1.0);
      _exitSpring.setTargetPosition(0.0);

      // 2. 设置进入行的物理目标
      // 进入行：当前状态是 0.0 (它是旧的配角)，目标是 1.0 (变成主角)
      _enterSpring.setPosition(0.0);
      _enterSpring.setTargetPosition(1.0);

      // 3. 启动 Ticker
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else {
      // 初始化或重置情况，直接同步
      _exitIndex = _enterIndex;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    controller.unregisterEvent(LyricEvent.reset, _reset);
    controller.activeIndexNotifiter.removeListener(onActiveIndexChange);
    controller.unregisterEvent(
        LyricEvent.playSwitchAnimation, onPlaySwitchAnimation);
    super.dispose();
  }
}