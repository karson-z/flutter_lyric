import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_line_view_model.dart';
import 'package:flutter_lyric/render/lyric_painter.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_highlight.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';

import '../core/lyric_style.dart';
import '../core/lyric_styles.dart';
import '../render/lyric_layout.dart';
import 'mixins/lyric_layout_mixin.dart';
import 'mixins/lyric_mask_mixin.dart';
import 'mixins/lyric_scroll_mixin.dart';
import 'mixins/lyric_touch_mixin.dart';

class LyricView extends StatefulWidget {
  final LyricController controller;
  final double? width;
  final double? height;
  final LyricStyle? style;
  const LyricView({
    Key? key,
    required this.controller,
    this.width,
    this.height,
    this.style,
  }) : super(key: key);

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView>
    with
        TickerProviderStateMixin,
        LyricLayoutMixin,
        LyricScrollMixin,
        LyricMaskMixin,
        LyricTouchMixin,
        LyricLineHightlightMixin,
        LyricLineSwitchMixin {
  // 提供 mixin 需要的属性访问
  @override
  LyricController get controller => widget.controller;

  @override
  LyricStyle get style => widget.style ?? LyricStyles.default1;
  // 布局相关状态
  @override
  LyricLayout? layout;

  @override
  var lyricSize = Size.zero;

  // 动画相关状态
  @override
  final scrollYNotifier = ValueNotifier<double>(0.0);

  // Apple Music Style ViewModels
  List<LyricLineViewModel> _lineViewModels = [];
  Ticker? _ticker;
  double _lastFrameTime = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker?.start();
    
    // 监听播放行变化，更新ViewModel目标状态
    controller.activeIndexNotifiter.addListener(_updateLineTargets);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    controller.activeIndexNotifiter.removeListener(_updateLineTargets);
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lineViewModels.isEmpty) return;
    
    final double currentTime = elapsed.inMicroseconds / 1000000.0;
    final double dt = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    // 防止第一帧dt过大
    if (dt > 0.1) return;

    bool needsRepaint = false;
    for (final vm in _lineViewModels) {
      vm.update(dt);
      if (vm.isAnimating) {
        needsRepaint = true;
      }
    }

    if (needsRepaint) {
      setState(() {});
    }
  }

  void _syncViewModels(LyricLayout layout) {
    // 调整数组大小以匹配行数
    if (_lineViewModels.length != layout.metrics.length) {
      if (_lineViewModels.length < layout.metrics.length) {
        final diff = layout.metrics.length - _lineViewModels.length;
        for (var i = 0; i < diff; i++) {
          _lineViewModels.add(LyricLineViewModel(
            initialScale: 1.0,  // 初始比例改为 1.0，避免一开始太小
            initialOpacity: 1.0, // 初始不透明
            initialBlur: 0.0     // 初始不模糊
          ));
        }
      } else {
        _lineViewModels.length = layout.metrics.length;
      }
    }
    // 立即更新一次目标位置
    _updateLineTargets();
  }

  void _updateLineTargets() {
    if (layout == null || _lineViewModels.isEmpty) return;

    final activeIndex = controller.activeIndexNotifiter.value;
    
    for (var i = 0; i < _lineViewModels.length; i++) {
      final vm = _lineViewModels[i];
      final dist = (i - activeIndex).abs();
      
      // 配置参数
      double targetScale = 1.0;
      double targetOpacity = 1.0;
      double targetBlur = 0.0;
      
      if (i == activeIndex) {
        // 当前行
        targetScale = 1.0; 
        targetOpacity = 1.0;
        targetBlur = 0.0;
      } else {
        // 非当前行 - 缓和参数，避免过度缩放和模糊
        // 限制最大影响距离为 4 行
        final distFactor = dist > 4 ? 4 : dist; 
        
        // 缩放：最小 0.8
        targetScale = 1.0 - (distFactor * 0.05); 
        if (targetScale < 0.8) targetScale = 0.8;
        
        // 透明度：最小 0.4
        targetOpacity = 1.0 - (distFactor * 0.15); 
        if (targetOpacity < 0.4) targetOpacity = 0.4;
        
        // 模糊：最大 1.0 (太大的模糊会导致文字完全不可见)
        targetBlur = distFactor * 0.3;
        if (targetBlur > 1.5) targetBlur = 1.5;
      }
      
      vm.setTransform(
        scale: targetScale,
        opacity: targetOpacity,
        blur: targetBlur,
      );
    }
  }

  @override
  void onLayoutChange(LyricLayout layout) {
    super.onLayoutChange(layout);
    _syncViewModels(layout); // 同步ViewModel
    updateHighlightWidth();
    updateScrollY(animate: false);
  }

  @override
  void didUpdateWidget(covariant LyricView oldWidget) {
    if (widget.style != oldWidget.style) {
      onStyleChange();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return wrapTouchWidget(
      context,
      SizedBox(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        child: Padding(
          padding: style.contentPadding.copyWith(top: 0, bottom: 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (size.width != lyricSize.width ||
                  size.height != lyricSize.height) {
                lyricSize = size;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  computeLyricLayout();
                });
              }
              if (layout == null) return const SizedBox.shrink();
              Widget result = buildLineSwitch((context, switchState) {
                return buildActiveHighlightWidth((double value) {
                  return ValueListenableBuilder(
                      valueListenable: scrollYNotifier,
                      builder: (context, double scrollY, child) {
                        return CustomPaint(
                          painter: LyricPainter(
                            layout: layout!,
                            viewModels: _lineViewModels, // 传入 ViewModels
                            onShowLineRectsChange: (rects) {
                              showLineRects = rects;
                            },
                            style: style,
                            playIndex: controller.activeIndexNotifiter.value,
                            activeHighlightWidth: value,
                            isSelecting: controller.isSelectingNotifier.value,
                            scrollY: scrollY,
                            onAnchorIndexChange: (index) {
                              scheduleMicrotask(() {
                                controller.selectedIndexNotifier.value = index;
                              });
                            },
                            switchState: switchState,
                          ),
                          size: lyricSize,
                        );
                      });
                });
              });
              result = wrapMaskIfNeed(result);
              return result;
            },
          ),
        ),
      ),
    );
  }
}
