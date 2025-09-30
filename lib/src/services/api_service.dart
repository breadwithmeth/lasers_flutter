import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device.dart';

class DeviceSchedule {
  final int id;
  final String? deviceId;
  final int windowStart; // minutes 0..1439
  final int windowEnd; // minutes 0..1439
  // Optional textual times (HH:MM). If present from backend they override minute fields meaning.
  final String? startTime; // e.g. "23:00"
  final String? endTime; // e.g. "04:00"
  final String sceneCmd;
  final String offMode; // OFF | SCENE_OFF
  final int priority;
  final bool enabled;

  DeviceSchedule({
    required this.id,
    required this.deviceId,
    required this.windowStart,
    required this.windowEnd,
    this.startTime,
    this.endTime,
    required this.sceneCmd,
    required this.offMode,
    required this.priority,
    required this.enabled,
  });

  bool get crossesMidnight => windowStart > windowEnd;

  bool isActiveAt(DateTime time) {
    final m = time.hour * 60 + time.minute;
    if (crossesMidnight) {
      return m >= windowStart || m < windowEnd;
    }
    return m >= windowStart && m < windowEnd;
  }

  String windowLabel() {
    String fmt(int v) {
      final h = (v ~/ 60).toString().padLeft(2, '0');
      final m = (v % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }

    final start = startTime ?? fmt(windowStart);
    final end = endTime ?? fmt(windowEnd);
    return '$start → $end' + (crossesMidnight ? ' (ночь)' : '');
  }

  factory DeviceSchedule.fromJson(Map<String, dynamic> j) {
    int _parseMinutes(dynamic v) => (v is int) ? v : int.tryParse('$v') ?? 0;
    int _hhmmToMinutes(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length != 2) return 0;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return (h.clamp(0, 23)) * 60 + (m.clamp(0, 59));
    }

    final startTime = j['startTime'] as String?;
    final endTime = j['endTime'] as String?;
    final windowStartRaw = j['windowStart'];
    final windowEndRaw = j['windowEnd'];
    final ws = startTime != null
        ? _hhmmToMinutes(startTime)
        : _parseMinutes(windowStartRaw);
    final we = endTime != null
        ? _hhmmToMinutes(endTime)
        : _parseMinutes(windowEndRaw);
    return DeviceSchedule(
      id: j['id'] as int,
      deviceId: j['deviceId'] as String?,
      windowStart: ws,
      windowEnd: we,
      startTime: startTime,
      endTime: endTime,
      sceneCmd: j['sceneCmd'] as String? ?? 'SCENE 1',
      offMode: j['offMode'] as String? ?? 'OFF',
      priority: j['priority'] as int? ?? 0,
      enabled: j['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson({bool includeId = false}) => {
    if (includeId) 'id': id,
    if (deviceId != null) 'deviceId': deviceId,
    'windowStart': windowStart,
    'windowEnd': windowEnd,
    if (startTime != null) 'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    'sceneCmd': sceneCmd,
    'offMode': offMode,
    'priority': priority,
    'enabled': enabled,
  };
}

class ApiService {
  final String baseUrl; // e.g. http://localhost:8080/api/v1
  String? _token;

  ApiService({required this.baseUrl});

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Map<String, String> _headers({bool jsonBody = true}) => {
    if (jsonBody) 'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<String> login({
    required String login,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final resp = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'login': login, 'password': password}),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final token = data['token'] as String?;
      if (token == null) throw Exception('No token field');
      _token = token;
      return token;
    } else {
      throw Exception('Login failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<List<DeviceCoords>> fetchDeviceCoords() async {
    final uri = Uri.parse('$baseUrl/devices/coords');
    final resp = await http.get(uri, headers: _headers(jsonBody: false));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = data['devices'] as List<dynamic>? ?? [];
      return list
          .map((e) => DeviceCoords.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('devices/coords failed: ${resp.statusCode}');
    }
  }

  Future<void> sendSimpleCommand(String deviceId, String path) async {
    final uri = Uri.parse('$baseUrl/device/$deviceId/$path');
    final resp = await http.post(uri, headers: _headers(jsonBody: false));
    if (resp.statusCode != 200) {
      throw Exception('Command $path failed (${resp.statusCode})');
    }
  }

  Future<void> sendCustomCommand(
    String deviceId,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl/device/$deviceId/custom');
    final resp = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Custom command failed: ${resp.statusCode}');
    }
  }

  Future<DeviceCoords> updateDeviceCoords(
    String deviceId,
    double lat,
    double lon,
  ) async {
    final uri = Uri.parse('$baseUrl/device/$deviceId');
    final resp = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode({'lat': lat, 'lon': lon}),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final dev = data['device'];
      if (dev is Map<String, dynamic>) {
        return DeviceCoords.fromJson(dev);
      }
      throw Exception('Unexpected response format');
    } else {
      throw Exception('update coords failed: ${resp.statusCode} ${resp.body}');
    }
  }

  // Basic polling for events (non-long version) using /events endpoint
  Future<List<LaserEvent>> fetchEvents(
    String deviceId, {
    int cursor = 0,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/events?device=$deviceId&cursor=$cursor&limit=$limit',
    );
    final resp = await http.get(uri, headers: _headers(jsonBody: false));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = data['events'] as List<dynamic>? ?? [];
      return list
          .map((e) => LaserEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('events failed: ${resp.statusCode}');
    }
  }

  // Long-polling minimal helper (cancellable via supplied isCancelled callback)
  Future<void> longPoll(
    String deviceId,
    void Function(LaserEvent) onEvent, {
    int startCursor = 0,
    int waitSeconds = 25,
    required bool Function() isCancelled,
  }) async {
    var cursor = startCursor;
    while (!isCancelled()) {
      final uri = Uri.parse(
        '$baseUrl/poll?device=$deviceId&cursor=$cursor&wait=$waitSeconds',
      );
      http.Response resp;
      try {
        resp = await http.get(uri, headers: _headers(jsonBody: false));
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
        continue;
      }
      if (resp.statusCode == 204) {
        // no content, continue
        continue;
      }
      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          final events = data['events'] as List<dynamic>? ?? [];
          for (final e in events) {
            final ev = LaserEvent.fromJson(e as Map<String, dynamic>);
            onEvent(ev);
            cursor = ev.id; // advance cursor to last id
          }
          if (data['cursor'] != null) {
            final newCursor = int.tryParse(data['cursor'].toString());
            if (newCursor != null) cursor = newCursor;
          }
        } catch (_) {}
      } else if (resp.statusCode == 401) {
        // auth lost
        break;
      } else {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  // ================= Schedules (superadmin) =================
  Future<List<DeviceSchedule>> fetchSchedules() async {
    final uri = Uri.parse('$baseUrl/device-schedules');
    final resp = await http.get(uri, headers: _headers(jsonBody: false));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = data is List ? data : (data['items'] as List? ?? []);
      return list
          .map((e) => DeviceSchedule.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('fetch schedules failed: ${resp.statusCode}');
    }
  }

  Future<DeviceSchedule> createSchedule(DeviceSchedule draft) async {
    final uri = Uri.parse('$baseUrl/device-schedules');
    final resp = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(draft.toJson()),
    );
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body);
      return DeviceSchedule.fromJson(
        (data is Map && data['schedule'] != null)
            ? data['schedule'] as Map<String, dynamic>
            : data as Map<String, dynamic>,
      );
    } else {
      throw Exception('create schedule failed: ${resp.statusCode}');
    }
  }

  Future<DeviceSchedule> updateSchedule(DeviceSchedule sched) async {
    final uri = Uri.parse('$baseUrl/device-schedules/${sched.id}');
    final resp = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode(sched.toJson()),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return DeviceSchedule.fromJson(
        (data is Map && data['schedule'] != null)
            ? data['schedule'] as Map<String, dynamic>
            : data as Map<String, dynamic>,
      );
    } else {
      throw Exception('update schedule failed: ${resp.statusCode}');
    }
  }

  Future<void> deleteSchedule(int id) async {
    final uri = Uri.parse('$baseUrl/device-schedules/$id');
    final resp = await http.delete(uri, headers: _headers(jsonBody: false));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('delete schedule failed: ${resp.statusCode}');
    }
  }
}
