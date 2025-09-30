import 'package:flutter/material.dart';
import '../../main.dart';
import '../services/api_service.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  bool _loading = false;
  String? _error;
  List<DeviceSchedule> _items = [];
  bool _didInit = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiProvider.of(context);
    try {
      final list = await api.fetchSchedules();
      list.sort((a, b) => b.priority.compareTo(a.priority));
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openEdit(DeviceSchedule? existing) async {
    final result = await showDialog<DeviceSchedule>(
      context: context,
      builder: (ctx) => _ScheduleDialog(initial: existing),
    );
    if (result != null) {
      final api = ApiProvider.of(context);
      try {
        if (existing == null) {
          final created = await api.createSchedule(result);
          setState(
            () =>
                _items = [..._items, created]
                  ..sort((a, b) => b.priority.compareTo(a.priority)),
          );
        } else {
          final updated = await api.updateSchedule(result);
          final idx = _items.indexWhere((e) => e.id == updated.id);
          if (idx != -1) {
            setState(() {
              _items[idx] = updated;
              _items.sort((a, b) => b.priority.compareTo(a.priority));
            });
          }
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  void _delete(DeviceSchedule sched) async {
    final api = ApiProvider.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить правило?'),
        content: Text('ID ${sched.id} (${sched.windowLabel()})'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteSchedule(sched.id);
      setState(() => _items.removeWhere((e) => e.id == sched.id));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписания'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => _openEdit(null),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _items.isEmpty
          ? const Center(child: Text('Нет правил'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: s.enabled
                        ? Colors.lightBlueAccent.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.2),
                    child: Text(
                      s.priority.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  title: Text(
                    s.sceneCmd + (s.deviceId != null ? ' • ${s.deviceId}' : ''),
                  ),
                  subtitle: Text('${s.windowLabel()}  |  off=${s.offMode}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openEdit(s),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(s),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  final DeviceSchedule? initial;
  const _ScheduleDialog({this.initial});
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _deviceCtrl;
  late TextEditingController _sceneCtrl;
  late TextEditingController _priorityCtrl;
  String _offMode = 'OFF';
  bool _enabled = true;
  int _startMinutes = 0;
  int _endMinutes = 0;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _deviceCtrl = TextEditingController(text: init?.deviceId ?? '');
    _startMinutes = init?.windowStart ?? 0;
    _endMinutes = init?.windowEnd ?? 0;
    _sceneCtrl = TextEditingController(text: init?.sceneCmd ?? 'SCENE 1');
    _priorityCtrl = TextEditingController(
      text: (init?.priority ?? 0).toString(),
    );
    _offMode = init?.offMode ?? 'OFF';
    _enabled = init?.enabled ?? true;
  }

  @override
  void dispose() {
    _deviceCtrl.dispose();
    _sceneCtrl.dispose();
    _priorityCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String v) => int.tryParse(v.trim());
  String _fmt(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  Future<void> _pick(bool start) async {
    final base = start ? _startMinutes : _endMinutes;
    final tod = TimeOfDay(hour: base ~/ 60, minute: base % 60);
    final res = await showTimePicker(
      context: context,
      initialTime: tod,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (res != null) {
      setState(() {
        final val = res.hour * 60 + res.minute;
        if (start) {
          _startMinutes = val;
        } else {
          _endMinutes = val;
        }
      });
    }
  }

  DeviceSchedule _buildDraft(int id) => DeviceSchedule(
    id: id,
    deviceId: _deviceCtrl.text.trim().isEmpty ? null : _deviceCtrl.text.trim(),
    windowStart: _startMinutes,
    windowEnd: _endMinutes,
    startTime: _fmt(_startMinutes),
    endTime: _fmt(_endMinutes),
    sceneCmd: _sceneCtrl.text.trim(),
    offMode: _offMode,
    priority: _parseInt(_priorityCtrl.text) ?? 0,
    enabled: _enabled,
  );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(isEdit ? 'Правка правила' : 'Новое правило'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              children: [
                TextFormField(
                  controller: _deviceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'deviceId (опц.)',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(true),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Начало окна',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(_fmt(_startMinutes)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(false),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Конец окна',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(_fmt(_endMinutes)),
                        ),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _sceneCtrl,
                  decoration: const InputDecoration(labelText: 'sceneCmd'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'required' : null,
                ),
                DropdownButtonFormField<String>(
                  value: _offMode,
                  decoration: const InputDecoration(labelText: 'offMode'),
                  items: const [
                    DropdownMenuItem(value: 'OFF', child: Text('OFF')),
                    DropdownMenuItem(
                      value: 'SCENE_OFF',
                      child: Text('SCENE_OFF'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _offMode = v);
                  },
                ),
                TextFormField(
                  controller: _priorityCtrl,
                  decoration: const InputDecoration(labelText: 'priority'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final x = _parseInt(v ?? '');
                    if (x == null) return 'int';
                    return null;
                  },
                ),
                SwitchListTile(
                  title: const Text('enabled'),
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (ctx) {
                    final crosses = _startMinutes > _endMinutes;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        crosses
                            ? 'Интервал через полночь'
                            : 'Интервал в пределах суток',
                        style: TextStyle(
                          fontSize: 12,
                          color: crosses ? Colors.orange : Colors.grey[600],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final draft = _buildDraft(widget.initial?.id ?? 0);
            Navigator.pop(context, draft);
          },
          child: Text(isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
