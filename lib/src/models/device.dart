class DeviceCoords {
  final String id;
  final double? lat;
  final double? lon;
  final DateTime? lastSeenAt;
  final bool scheduleHas;
  final bool scheduleActive;

  DeviceCoords({
    required this.id,
    this.lat,
    this.lon,
    this.lastSeenAt,
    this.scheduleHas = false,
    this.scheduleActive = false,
  });

  factory DeviceCoords.fromJson(Map<String, dynamic> json) {
    const serverOffset = Duration(hours: 5); // Server timezone +05:00
    DateTime? _parseServerTime(dynamic v) {
      if (v == null) return null;
      final raw = v.toString();
      if (raw.isEmpty) return null;
      try {
        // Support numeric epoch (ms) from server
        if (v is int) {
          // Assume epoch milliseconds are UTC (if actually server-local +05 adjust here)
          return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
        }
        if (RegExp(r'^\d{10,}$').hasMatch(raw)) {
          final ms = int.tryParse(raw);
          if (ms != null) {
            return DateTime.fromMillisecondsSinceEpoch(
              ms,
              isUtc: true,
            ).toLocal();
          }
        }
        final hasTz = RegExp(r'([+-]\d\d:?\d\d)|Z\$').hasMatch(raw);
        DateTime parsed = DateTime.parse(raw);
        if (hasTz) {
          return parsed.toLocal();
        } else {
          // Treat naive string as server local (+05:00). Convert to UTC then to device local.
          final naive = DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
          final utc = naive.subtract(serverOffset);
          return utc.toLocal();
        }
      } catch (_) {
        return null;
      }
    }

    return DeviceCoords(
      id: json['id'] as String,
      lat: (json['lat'] is num) ? (json['lat'] as num).toDouble() : null,
      lon: (json['lon'] is num) ? (json['lon'] as num).toDouble() : null,
      lastSeenAt: _parseServerTime(json['lastSeenAt']),
      scheduleHas: json['scheduleHas'] == true,
      scheduleActive: json['scheduleActive'] == true,
    );
  }
}

class LaserEvent {
  final int id;
  final DateTime ts;
  final String cmd;
  final dynamic val;
  final String? raw;

  LaserEvent({
    required this.id,
    required this.ts,
    required this.cmd,
    this.val,
    this.raw,
  });

  factory LaserEvent.fromJson(Map<String, dynamic> json) {
    const serverOffset = Duration(hours: 5); // Server timezone +05:00
    DateTime _parseTs(String raw) {
      try {
        final hasTz = RegExp(r'([+-]\d\d:?\d\d)|Z\$').hasMatch(raw);
        DateTime parsed = DateTime.parse(raw);
        if (hasTz) {
          return parsed.toLocal();
        } else {
          final naive = DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
          final utc = naive.subtract(serverOffset);
          return utc.toLocal();
        }
      } catch (_) {
        return DateTime.now();
      }
    }

    return LaserEvent(
      id: json['id'] as int,
      ts: _parseTs(json['ts'] as String),
      cmd: json['cmd'] as String,
      val: json['val'],
      raw: json['raw'] as String?,
    );
  }
}

class DeviceStatus {
  final int id;
  final DateTime ts;
  final String state;
  final double? deviation;

  DeviceStatus({
    required this.id,
    required this.ts,
    required this.state,
    this.deviation,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    DateTime _parseTs(String raw) {
      try {
        return DateTime.parse(raw).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return DeviceStatus(
      id: json['id'] as int,
      ts: _parseTs(json['ts'] as String),
      state: json['state'] as String? ?? 'UNKNOWN',
      deviation: _toDouble(json['deviation']),
    );
  }
}
