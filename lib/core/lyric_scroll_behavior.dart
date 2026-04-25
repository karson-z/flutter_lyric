import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

abstract class ScrollBehaviorConfig {
  Animation<double> applyAnimation({
    required AnimationController controller,
    required double begin,
    required double end,
  });
}

class CurvedScrollConfig extends ScrollBehaviorConfig {
  final Curve curve;
  final Duration Function(double offset) durationCalculator;

  CurvedScrollConfig({
    required this.curve,
    required this.durationCalculator,
  });

  @override
  Animation<double> applyAnimation({
    required AnimationController controller,
    required double begin,
    required double end,
  }) {
    final offset = (begin - end).abs();

    controller.duration = durationCalculator(offset);

    if (controller.duration == Duration.zero) {
      return AlwaysStoppedAnimation(end);
    }

    final curvedAnimation = CurvedAnimation(
      parent: controller,
      curve: curve,
    );

    final animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(curvedAnimation);

    controller.forward(from: 0);
    return animation;
  }
}

class SpringScrollConfig extends ScrollBehaviorConfig {
  final SpringDescription springDescription;
  final double initialVelocity;

  SpringScrollConfig({
    required this.springDescription,
    this.initialVelocity = 0.0,
  });

  @override
  Animation<double> applyAnimation({
    required AnimationController controller,
    required double begin,
    required double end,
  }) {
    final simulation = SpringSimulation(
      springDescription,
      begin,
      end,
      initialVelocity,
    );

    controller.animateWith(simulation);

    return controller;
  }
}