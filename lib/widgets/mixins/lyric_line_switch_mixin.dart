import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';

class LyricLineSwitchState {
  double animationValue = 0.0;
  int activeIndex = -1;
  int previousIndex = -1;

  LyricLineSwitchState({
    required this.animationValue,
    required this.activeIndex,
    required this.previousIndex,
  });
}

mixin LyricLineSwitchMixin<T extends StatefulWidget>
    on State<T>, LyricLayoutMixin<T>, TickerProviderStateMixin<T> {
  int _previousIndex = -1;
  int _currentIndex = -1;

  late final AnimationController _staggeredController;

  @override
  void initState() {
    super.initState();
    controller.registerEvent(LyricEvent.reset, _reset);
    _staggeredController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400), // Base duration
    );
    _currentIndex = controller.activeIndexNotifiter.value;
    controller.activeIndexNotifiter.addListener(onActiveIndexChange);
  }

  _reset(_) {
    _previousIndex = -1;
    _currentIndex = -1;
    _staggeredController.value = 1.0;
  }

  buildLineSwitch(
      Widget Function(BuildContext context, LyricLineSwitchState state)
          builder) {
    return AnimatedBuilder(
      animation: _staggeredController,
      builder: (context, child) {
        return builder(
            context,
            LyricLineSwitchState(
              animationValue: _staggeredController.value,
              activeIndex: _currentIndex,
              previousIndex: _previousIndex,
            ));
      },
    );
  }

  onActiveIndexChange() {
    final newIndex = controller.activeIndexNotifiter.value;
    if (newIndex == _currentIndex) return;

    _previousIndex = _currentIndex;
    _currentIndex = newIndex;

    // Restart animation
    _staggeredController.reset();
    _staggeredController.forward();
  }

  @override
  void dispose() {
    controller.unregisterEvent(LyricEvent.reset, _reset);
    _staggeredController.dispose();
    controller.activeIndexNotifiter.removeListener(onActiveIndexChange);
    super.dispose();
  }
}
