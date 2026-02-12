import 'dart:math' as math;

/// 对应 TS 中的 SpringParams
class SpringParams {
  final double mass;
  final double damping;
  final double stiffness;
  final bool soft;

  const SpringParams({
    this.mass = 1.0,
    this.damping = 10.0,
    this.stiffness = 100.0,
    this.soft = false,
  });

  SpringParams apply(SpringOptions options) {
    return SpringParams(
      mass: options.mass ?? mass,
      damping: options.damping ?? damping,
      stiffness: options.stiffness ?? stiffness,
      soft: options.soft ?? soft,
    );
  }
}

/// 用于更新部分参数
class SpringOptions {
  final double? mass;
  final double? damping;
  final double? stiffness;
  final bool? soft;

  const SpringOptions({this.mass, this.damping, this.stiffness, this.soft});
}

typedef Solver = double Function(double t);

/// 数值求导：模拟 TS 中的 getVelocity
Solver getVelocity(Solver solver) {
  return (double t) {
    const double h = 0.0001; // 精度
    return (solver(t + h) - solver(t)) / h;
  };
}

class Spring {
  double _currentPosition = 0;
  double _targetPosition = 0;
  double _currentTime = 0;

  SpringParams _params = const SpringParams();

  late Solver _currentSolver;
  late Solver _getV;
  late Solver _getV2;

  // 队列逻辑复刻
  _QueueParams? _queueParams;
  _QueuePosition? _queuePosition;

  Spring({double initialPosition = 0}) {
    _targetPosition = initialPosition;
    _currentPosition = initialPosition;
    _currentSolver = (t) => _targetPosition;
    _getV = (t) => 0;
    _getV2 = (t) => 0;
  }

  void _resetSolver() {
    final curV = _getV(_currentTime);
    _currentTime = 0;
    _currentSolver = _solveSpring(
      _currentPosition,
      curV,
      _targetPosition,
      0,
      _params,
    );
    _getV = getVelocity(_currentSolver);
    _getV2 = getVelocity(_getV);
  }

  bool arrived() {
    return (_targetPosition - _currentPosition).abs() < 0.01 &&
        _getV(_currentTime).abs() < 0.01 &&
        _getV2(_currentTime).abs() < 0.01 &&
        _queueParams == null &&
        _queuePosition == null;
  }

  void setPosition(double targetPosition) {
    _targetPosition = targetPosition;
    _currentPosition = targetPosition;
    _currentSolver = (t) => _targetPosition;
    _getV = (t) => 0;
    _getV2 = (t) => 0;
  }

  /// [delta] 是距离上一帧的时间（秒）
  void update(double delta) {
    _currentTime += delta;
    _currentPosition = _currentSolver(_currentTime);

    if (_queueParams != null) {
      _queueParams!.time -= delta;
      if (_queueParams!.time <= 0) {
        updateParams(_queueParams!.options);
        _queueParams = null;
      }
    }
    if (_queuePosition != null) {
      _queuePosition!.time -= delta;
      if (_queuePosition!.time <= 0) {
        setTargetPosition(_queuePosition!.position);
        _queuePosition = null;
      }
    }

    if (arrived()) {
      setPosition(_targetPosition);
    }
  }

  void updateParams(SpringOptions options, {double delay = 0}) {
    if (delay > 0) {
      _queueParams = _QueueParams(options, delay);
    } else {
      _queueParams = null;
      _params = _params.apply(options);
      _resetSolver();
    }
  }

  void setTargetPosition(double targetPosition, {double delay = 0}) {
    if (delay > 0) {
      _queuePosition = _QueuePosition(targetPosition, delay);
    } else {
      _queuePosition = null;
      _targetPosition = targetPosition;
      _resetSolver();
    }
  }

  double getCurrentPosition() => _currentPosition;
  double getCurrentVelocity() => _getV(_currentTime);
}

class _QueueParams {
  final SpringOptions options;
  double time;
  _QueueParams(this.options, this.time);
}

class _QueuePosition {
  final double position;
  double time;
  _QueuePosition(this.position, this.time);
}

/// 核心物理求解算法
Solver _solveSpring(
    double from,
    double velocity,
    double to,
    double delay,
    SpringParams params,
    ) {
  final soft = params.soft;
  final stiffness = params.stiffness;
  final damping = params.damping;
  final mass = params.mass;
  final delta = to - from;

  // 临界阻尼 / 过阻尼 (Critical / Overdamped)
  if (soft || 1.0 <= damping / (2.0 * math.sqrt(stiffness * mass))) {
    final angularFrequency = -math.sqrt(stiffness / mass);
    final leftover = -angularFrequency * delta - velocity;
    return (t) {
      t -= delay;
      if (t < 0) return from;
      return to - (delta + t * leftover) * math.exp(t * angularFrequency);
    };
  }

  // 欠阻尼 (Underdamped - 有回弹)
  final dampingFrequency = math.sqrt(4.0 * mass * stiffness - math.pow(damping, 2.0));
  final leftover = (damping * delta - 2.0 * mass * velocity) / dampingFrequency;
  final dfm = (0.5 * dampingFrequency) / mass;
  final dm = -(0.5 * damping) / mass;

  return (t) {
    t -= delay;
    if (t < 0) return from;
    return to -
        (math.cos(t * dfm) * delta + math.sin(t * dfm) * leftover) *
            math.exp(t * dm);
  };
}