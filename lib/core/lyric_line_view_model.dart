import 'dart:math';

import 'package:flutter_lyric/core/spring.dart';

enum LyricLineRenderMode {
  solid,
  gradient,
}

class LyricLineViewModel {
  final Spring posY;
  final Spring scale;
  final Spring opacity;
  final Spring blur;

  // Cache current values to avoid calling getCurrentPosition repeatedly in paint
  double currentPosY = 0;
  double currentScale = 1.0;
  double currentOpacity = 1.0;
  double currentBlur = 0;
  
  LyricLineRenderMode renderMode = LyricLineRenderMode.solid;
  
  // Word-level mask alpha states
  double currentBrightAlpha = 1.0;
  double currentDarkAlpha = 0.2;
  double targetBrightAlpha = 1.0;
  double targetDarkAlpha = 0.2;

  LyricLineViewModel({
    double initialY = 0,
    double initialScale = 1.0,
    double initialOpacity = 1.0,
    double initialBlur = 0,
  })  : posY = Spring(initialY)
          ..updateParams(SpringParams(mass: 0.9, damping: 15, stiffness: 90)),
        scale = Spring(initialScale * 100)
          ..updateParams(SpringParams(mass: 2, damping: 25, stiffness: 100)),
        opacity = Spring(initialOpacity),
        blur = Spring(initialBlur);

  void setTransform({
    double? top,
    double? scale,
    double? opacity,
    double? blur,
    bool force = false,
    double delay = 0,
    LyricLineRenderMode? mode,
  }) {
    if (top != null) {
      if (force) {
        posY.setPosition(top);
      } else {
        posY.setTargetPosition(top, delay);
      }
    }
    if (scale != null) {
      // TS uses 0-100 scale base
      final targetScale = scale * 100;
      if (force) {
        this.scale.setPosition(targetScale);
      } else {
        this.scale.setTargetPosition(targetScale);
      }
    }
    if (opacity != null) {
      if (force) {
        this.opacity.setPosition(opacity);
      } else {
        this.opacity.setTargetPosition(opacity);
      }
    }
    if (blur != null) {
      // Clamp blur to reasonable values if needed
      final targetBlur = min(32.0, blur);
      if (force) {
        this.blur.setPosition(targetBlur);
      } else {
        this.blur.setTargetPosition(targetBlur, delay);
      }
    }
    if (mode != null) {
      renderMode = mode;
    }
  }

  void update(double dt) {
    posY.update(dt);
    scale.update(dt);
    opacity.update(dt);
    blur.update(dt);

    currentPosY = posY.getCurrentPosition();
    currentScale = scale.getCurrentPosition() / 100.0;
    currentOpacity = opacity.getCurrentPosition();
    currentBlur = blur.getCurrentPosition();
  }

  bool get isAnimating {
    return !posY.arrived() ||
        !scale.arrived() ||
        !opacity.arrived() ||
        !blur.arrived();
  }

}
