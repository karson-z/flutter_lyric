import 'dart:math';

/// Spring parameters for the damped harmonic oscillator.
class SpringParams {
  double mass; // = 1.0
  double damping; // = 10.0
  double stiffness; // = 100.0
  bool soft; // = false

  SpringParams({
    this.mass = 1.0,
    this.damping = 10.0,
    this.stiffness = 100.0,
    this.soft = false,
  });

  SpringParams copyWith({
    double? mass,
    double? damping,
    double? stiffness,
    bool? soft,
  }) {
    return SpringParams(
      mass: mass ?? this.mass,
      damping: damping ?? this.damping,
      stiffness: stiffness ?? this.stiffness,
      soft: soft ?? this.soft,
    );
  }
}

typedef Solver = double Function(double t);

class Spring {
  double _currentPosition = 0;
  double _targetPosition = 0;
  double _currentTime = 0;
  SpringParams _params = SpringParams();
  late Solver _currentSolver;
  late Solver _getV;
  // ignore: unused_field
  late Solver _getV2;

  // Queue for delayed parameter updates or position updates
  _QueueItem? _queueParams;
  _QueueItem? _queuePosition;

  Spring([double currentPosition = 0]) {
    _targetPosition = currentPosition;
    _currentPosition = _targetPosition;
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
    _getV = _getVelocity(_currentSolver);
    _getV2 = _getVelocity(_getV);
  }

  bool arrived() {
    return (_targetPosition - _currentPosition).abs() < 0.01 &&
        _getV(_currentTime).abs() < 0.01 &&
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

  void update(double delta) {
    _currentTime += delta;
    _currentPosition = _currentSolver(_currentTime);

    if (_queueParams != null) {
      _queueParams!.time -= delta;
      if (_queueParams!.time <= 0) {
        updateParams(_queueParams!.params!, 0);
        _queueParams = null;
      }
    }

    if (_queuePosition != null) {
      _queuePosition!.time -= delta;
      if (_queuePosition!.time <= 0) {
        setTargetPosition(_queuePosition!.position!, 0);
        _queuePosition = null;
      }
    }

    if (arrived()) {
      setPosition(_targetPosition);
    }
  }

  void updateParams(SpringParams params, [double delay = 0]) {
    if (delay > 0) {
      _queueParams = _QueueItem(params: params, time: delay);
    } else {
      _queuePosition = null;
      _params = params;
      _resetSolver();
    }
  }

  void setTargetPosition(double targetPosition, [double delay = 0]) {
    if (delay > 0) {
      _queuePosition = _QueueItem(position: targetPosition, time: delay);
    } else {
      _queuePosition = null;
      _targetPosition = targetPosition;
      _resetSolver();
    }
  }

  double getCurrentPosition() {
    return _currentPosition;
  }
}

class _QueueItem {
  SpringParams? params;
  double? position;
  double time;

  _QueueItem({this.params, this.position, required this.time});
}

Solver _solveSpring(
  double from,
  double velocity,
  double to,
  double delay,
  SpringParams? params,
) {
  final soft = params?.soft ?? false;
  final stiffness = params?.stiffness ?? 100;
  final damping = params?.damping ?? 10;
  final mass = params?.mass ?? 1;
  final delta = to - from;

  if (soft || 1.0 <= damping / (2.0 * sqrt(stiffness * mass))) {
    final angularFrequency = -sqrt(stiffness / mass);
    final leftover = -angularFrequency * delta - velocity;
    return (t) {
      t -= delay;
      if (t < 0) return from;
      return to - (delta + t * leftover) * pow(e, t * angularFrequency);
    };
  }

  final dampingFrequency = sqrt(4.0 * mass * stiffness - pow(damping, 2));
  final leftover = (damping * delta - 2.0 * mass * velocity) / dampingFrequency;
  final dfm = (0.5 * dampingFrequency) / mass;
  final dm = -(0.5 * damping) / mass;

  return (t) {
    t -= delay;
    if (t < 0) return from;
    return to -
        (cos(t * dfm) * delta + sin(t * dfm) * leftover) * pow(e, t * dm);
  };
}

Solver _getVelocity(Solver solver) {
  const h = 0.0001;
  return (t) => (solver(t + h) - solver(t)) / h;
}
