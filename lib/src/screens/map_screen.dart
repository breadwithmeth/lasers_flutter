// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'schedules_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<DeviceCoords> _devices = [];
  bool _loading = false;
  String? _error;
  Timer? _refreshTimer;
  String? _selectedId;
  // Events & polling
  List<LaserEvent> _events = [];
  int _eventCursor = 0;
  bool _polling = false;
  bool _showEvents = true;
  // Filtering & sorting
  String _search = '';
  bool _sortByActivity = true; // activity desc vs id asc
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // actual loading moved to didChangeDependencies (need Inherited context)
  }

  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _load();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _load(silent: true),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _polling = false;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    setState(() => _error = null);
    final api = ApiProvider.of(context);
    try {
      final list = await api.fetchDeviceCoords();
      list.sort((a, b) => a.id.compareTo(b.id));
      setState(() => _devices = list);
      if (list.isNotEmpty) {
        if (_selectedId != null) {
          final sel = list.firstWhere(
            (d) => d.id == _selectedId,
            orElse: () => list.first,
          );
          if (sel.lat != null && sel.lon != null) {
            _mapController.move(
              LatLng(sel.lat!, sel.lon!),
              _mapController.camera.zoom,
            );
          }
        } else {
          final center = _computeCenter(list);
          if (center != null) {
            _mapController.move(
              center,
              _mapController.camera.zoom,
            ); // keep zoom
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  LatLng? _computeCenter(List<DeviceCoords> list) {
    final coords = list.where((d) => d.lat != null && d.lon != null).toList();
    if (coords.isEmpty) return null;
    final lat =
        coords.map((e) => e.lat!).reduce((a, b) => a + b) / coords.length;
    final lon =
        coords.map((e) => e.lon!).reduce((a, b) => a + b) / coords.length;
    return LatLng(lat, lon);
  }

  Future<void> _sendCommand(
    DeviceCoords d,
    Future<void> Function(String id) action,
  ) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await action(d.id);
      scaffold.showSnackBar(
        SnackBar(content: Text('Команда отправлена ${d.id}')),
      );
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _openDeviceSheet(DeviceCoords d) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _DeviceSheet(
            device: d,
            onCommand: _sendCommand,
            onCustom: _openCustomCommandDialog,
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomCommandDialog(DeviceCoords device) async {
    final cmdController = TextEditingController();
    final valController = TextEditingController();
    final rawController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final api = ApiProvider.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Команда для ${device.id}'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: cmdController,
                    decoration: const InputDecoration(
                      labelText: 'cmd (например SCENE 1 или OFF)',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Обязательное поле'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valController,
                    decoration: const InputDecoration(
                      labelText: 'val (необязательно)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rawController,
                    decoration: const InputDecoration(
                      labelText: 'raw (необязательно)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final body = <String, dynamic>{
                  'cmd': cmdController.text.trim(),
                };
                if (valController.text.trim().isNotEmpty) {
                  final valRaw = valController.text.trim();
                  final parsed = int.tryParse(valRaw);
                  body['val'] = parsed ?? valRaw;
                }
                if (rawController.text.trim().isNotEmpty) {
                  body['raw'] = rawController.text.trim();
                }
                await api.sendCustomCommand(device.id, body);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Отправлено ${body['cmd']}')),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                }
              }
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (result == true) {
      // reserved for future refresh logic
    }
  }

  void _focusDevice(DeviceCoords d) {
    setState(() => _selectedId = d.id);
    if (d.lat != null && d.lon != null) {
      _mapController.move(LatLng(d.lat!, d.lon!), ninthZoom());
    }
    _startPolling();
  }

  void _startPolling() {
    if (_polling || _selectedId == null) return;
    _polling = true;
    final api = ApiProvider.of(context);
    Future.microtask(() async {
      while (_polling && mounted && _selectedId != null) {
        try {
          await api.longPoll(
            _selectedId!,
            (ev) {
              _eventCursor = ev.id;
              _events.insert(0, ev);
              if (_events.length > 200) {
                _events.removeRange(200, _events.length);
              }
              if (mounted) setState(() {});
            },
            startCursor: _eventCursor,
            isCancelled: () => !_polling || !mounted || _selectedId == null,
          );
        } catch (_) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    });
  }

  double ninthZoom() {
    // choose a reasonable zoom when selecting a device; if already zoomed in keep it
    final current = _mapController.camera.zoom;
    return current < 9 ? 9 : current; // 9 is a moderate city-level zoom
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    ApiProvider.of(context).clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(onLoggedIn: (t) async {})),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Iterable<DeviceCoords> filtered = _devices.where(
      (d) => d.id.toLowerCase().contains(_search.toLowerCase()),
    );
    if (_sortByActivity) {
      filtered = filtered.toList()
        ..sort(
          (a, b) => (b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );
    }
    final visibleDevices = filtered.toList();

    final markers = visibleDevices
        .where((d) => d.lat != null && d.lon != null)
        .map(
          (d) => Marker(
            width: d.id == _selectedId ? 56 : 42,
            height: d.id == _selectedId ? 56 : 42,
            point: LatLng(d.lat!, d.lon!),
            child: GestureDetector(
              onTap: () => _openDeviceSheet(d),
              child: _LaserMarker(device: d, selected: d.id == _selectedId),
            ),
          ),
        )
        .toList();

    final center =
        _computeCenter(_devices) ??
        const LatLng(55.751244, 37.618423); // Moscow fallback

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lasers'),
        actions: [
          IconButton(
            tooltip: 'Расписания',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SchedulesScreen()),
              );
            },
            icon: const Icon(Icons.schedule),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : () => _load(),
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Выход',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              constraints.maxWidth >
              constraints.maxHeight; // landscape or large tablet
          final mapWidget = _buildMapStack(center, markers);
          final listWidget = _buildDeviceList(visibleDevices);
          if (isWide) {
            return Row(
              children: [
                Expanded(child: mapWidget),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: listWidget),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: mapWidget),
              const Divider(height: 1, thickness: 1),
              Expanded(child: listWidget),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'fitAll',
            tooltip: 'Показать все',
            onPressed: () {
              final center = _computeCenter(_devices);
              if (center != null) _mapController.move(center, 5);
            },
            child: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'events',
            tooltip: 'События',
            onPressed: () => setState(() => _showEvents = !_showEvents),
            child: Icon(_showEvents ? Icons.event_note : Icons.event),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'refresh',
            tooltip: 'Обновить',
            onPressed: () => _load(),
            child: const Icon(Icons.sync),
          ),
        ],
      ),
    );
  }

  Widget _buildMapStack(LatLng center, List<Marker> markers) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 5,
            interactionOptions: const InteractionOptions(
              flags: ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'lasers_flutter',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        if (_showEvents && _selectedId != null)
          Positioned(
            right: 12,
            bottom: 12,
            width: 280,
            height: 260,
            child: _EventsPanel(
              deviceId: _selectedId!,
              events: _events,
              onClose: () => setState(() => _showEvents = false),
              onRefresh: () async {
                final api = ApiProvider.of(context);
                try {
                  final newEvents = await api.fetchEvents(
                    _selectedId!,
                    cursor: 0,
                    limit: 50,
                  );
                  setState(() {
                    _events = newEvents.reversed.toList();
                    if (_events.isNotEmpty) _eventCursor = _events.first.id;
                  });
                } catch (_) {}
              },
            ),
          ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: Material(
              color: Colors.red.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeviceList(List<DeviceCoords> list) {
    if (list.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return const Center(child: Text('Нет устройств'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Поиск...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchCtrl.clear();
                                _search = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              IconButton(
                tooltip: _sortByActivity ? 'Сорт: активные ↑' : 'Сорт: ID',
                onPressed: () =>
                    setState(() => _sortByActivity = !_sortByActivity),
                icon: Icon(
                  _sortByActivity ? Icons.flash_on : Icons.sort_by_alpha,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1),
            itemBuilder: (ctx, i) {
              final d = list[i];
              final selected = d.id == _selectedId;
              final canFocus = d.lat != null && d.lon != null;
              final lastSeenStr = d.lastSeenAt != null
                  ? _formatRelative(d.lastSeenAt!)
                  : '—';
              return InkWell(
                onTap: canFocus ? () => _focusDevice(d) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: selected
                      ? Colors.lightBlueAccent.withValues(alpha: 0.08)
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 18,
                        color: selected
                            ? Colors.lightBlueAccent
                            : (canFocus ? Colors.grey[400] : Colors.grey[700]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.id,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.blueAccent
                                    : const Color(0xFF1F2430),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'last: $lastSeenStr',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Изменить координаты',
                        onPressed: () => _editCoords(d),
                        icon: const Icon(Icons.edit_location_alt, size: 20),
                      ),
                      if (canFocus)
                        IconButton(
                          tooltip: 'Команды',
                          onPressed: () => _openDeviceSheet(d),
                          icon: const Icon(Icons.tune, size: 20),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _editCoords(DeviceCoords d) async {
    final latCtrl = TextEditingController(
      text: d.lat?.toStringAsFixed(6) ?? '',
    );
    final lonCtrl = TextEditingController(
      text: d.lon?.toStringAsFixed(6) ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final api = ApiProvider.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Координаты ${d.id}'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: latCtrl,
                  decoration: const InputDecoration(labelText: 'lat'),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) => (v == null || double.tryParse(v) == null)
                      ? 'Неверно'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: lonCtrl,
                  decoration: const InputDecoration(labelText: 'lon'),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) => (v == null || double.tryParse(v) == null)
                      ? 'Неверно'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final lat = double.parse(latCtrl.text.trim());
                final lon = double.parse(lonCtrl.text.trim());
                final updated = await api.updateDeviceCoords(d.id, lat, lon);
                final idx = _devices.indexWhere((e) => e.id == d.id);
                if (idx != -1) {
                  setState(() {
                    _devices[idx] = updated;
                  });
                  _focusDevice(updated);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка сохранения: $e')),
                  );
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result == true) {
      // Optionally reload
    }
  }
}

class _LaserMarker extends StatelessWidget {
  final DeviceCoords device;
  final bool selected;
  const _LaserMarker({required this.device, required this.selected});

  @override
  Widget build(BuildContext context) {
    final active =
        device.lastSeenAt != null &&
        DateTime.now().difference(device.lastSeenAt!).inMinutes < 5;
    final baseColor = selected ? Colors.amberAccent : const Color(0xFF1F2430);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: active
              ? [
                  (selected ? Colors.orangeAccent : Colors.greenAccent)
                      .withValues(alpha: 0.9),
                  (selected ? Colors.deepOrange : Colors.green).withValues(
                    alpha: 0.18,
                  ),
                ]
              : [
                  Colors.grey.shade300,
                  Colors.grey.shade500.withValues(alpha: 0.25),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: active
                ? (selected
                      ? Colors.orangeAccent.withValues(alpha: 0.7)
                      : Colors.greenAccent.withValues(alpha: 0.5))
                : (selected
                      ? Colors.orangeAccent.withValues(alpha: 0.35)
                      : Colors.grey.withValues(alpha: 0.45)),
            blurRadius: selected ? 14 : 8,
            spreadRadius: selected ? 4 : 2,
          ),
          if (selected)
            BoxShadow(
              color: Colors.orangeAccent.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 6,
            ),
        ],
        border: selected
            ? Border.all(color: Colors.orangeAccent, width: 2)
            : Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1),
      ),
      child: Center(
        child: Text(
          device.id,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: baseColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EventsPanel extends StatelessWidget {
  final String deviceId;
  final List<LaserEvent> events;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;
  const _EventsPanel({
    required this.deviceId,
    required this.events,
    required this.onClose,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      surfaceTintColor: Colors.white,
      color: Colors.white.withValues(alpha: 0.97),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE5E9F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Events: $deviceId',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2430),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить историю',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                IconButton(
                  tooltip: 'Закрыть панель',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Text(
                      'Нет событий',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.zero,
                    itemCount: events.length,
                    itemBuilder: (ctx, i) {
                      final ev = events[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '#${ev.id}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ev.cmd,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2430),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _fmt(ev.ts),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                            if (ev.raw != null)
                              Text(
                                ev.raw!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF475569),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime ts) {
    final h = ts.toLocal().hour.toString().padLeft(2, '0');
    final m = ts.toLocal().minute.toString().padLeft(2, '0');
    final s = ts.toLocal().second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _DeviceSheet extends StatelessWidget {
  final DeviceCoords device;
  final Future<void> Function(DeviceCoords, Future<void> Function(String))
  onCommand;
  final Future<void> Function(DeviceCoords) onCustom;
  const _DeviceSheet({
    required this.device,
    required this.onCommand,
    required this.onCustom,
  });

  Future<void> _openScenesDialog(BuildContext context, ApiService api) async {
    final scenes = [1, 2];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сцены для ${device.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in scenes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_circle_outline),
                title: Text('SCENE $s'),
                onTap: () async {
                  try {
                    await onCommand(
                      device,
                      (id) => api.sendSimpleCommand(id, 'scene/$s'),
                    );
                  } finally {
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiProvider.of(context);
    final last = device.lastSeenAt != null
        ? _fmtWithTz(device.lastSeenAt!)
        : '—';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  device.id,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            'Координаты: ${device.lat?.toStringAsFixed(5) ?? '-'}, ${device.lon?.toStringAsFixed(5) ?? '-'}',
          ),
          Text('Последняя активность: $last'),
          if (device.scheduleHas)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    device.scheduleActive
                        ? Icons.schedule
                        : Icons.schedule_outlined,
                    size: 16,
                    color: device.scheduleActive
                        ? Colors.orange
                        : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      device.scheduleActive
                          ? 'Активно расписание (ручные команды временно заблокированы)'
                          : 'Есть расписание',
                      style: TextStyle(
                        fontSize: 12,
                        color: device.scheduleActive
                            ? Colors.orange[800]
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CmdButton(
                label: 'Scenes',
                onTap: device.scheduleActive
                    ? null
                    : () => _openScenesDialog(context, api),
              ),
              _CmdButton(
                label: 'OFF',
                danger: true,
                onTap: device.scheduleActive
                    ? null
                    : () => onCommand(
                        device,
                        (id) => api.sendCustomCommand(id, const {'cmd': 'OFF'}),
                      ),
              ),
              _CmdButton(
                label: 'Custom',
                onTap: device.scheduleActive ? null : () => onCustom(device),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmtWithTz(DateTime dt) {
  final local = dt.toLocal();
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final y = local.year.toString().padLeft(4, '0');
  final mo = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$y-$mo-$d $hh:$mm:$ss $sign$h:$m';
}

class _CmdButton extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback? onTap;
  const _CmdButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : Colors.lightBlueAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: onTap == null
              ? Colors.grey.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.15),
          border: Border.all(
            color: onTap == null
                ? Colors.grey.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
            color: onTap == null ? Colors.grey.withValues(alpha: 0.7) : color,
          ),
        ),
      ),
    );
  }
}
