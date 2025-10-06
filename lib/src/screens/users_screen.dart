import 'package:flutter/material.dart';
import '../../main.dart';
import '../services/api_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _loading = false;
  String? _error;
  List<User> _users = [];
  bool _includeInactive = true;
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
      final list = await api.fetchUsers(includeInactive: _includeInactive);
      list.sort((a, b) => a.id.compareTo(b.id));
      setState(() => _users = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final api = ApiProvider.of(context);
    final res = await showDialog<_UserDraft>(
      context: context,
      builder: (ctx) => _UserDialog(),
    );
    if (res == null) return;
    try {
      final u = await api.createUser(
        username: res.username,
        email: res.email,
        password: res.password!,
        role: res.role,
      );
      setState(
        () => _users = [..._users, u]..sort((a, b) => a.id.compareTo(b.id)),
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Создан пользователь ${u.username}')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка создания: $e')));
    }
  }

  Future<void> _edit(User user) async {
    final api = ApiProvider.of(context);
    final res = await showDialog<_UserDraft>(
      context: context,
      builder: (ctx) => _UserDialog(existing: user),
    );
    if (res == null) return;
    try {
      final updated = await api.updateUser(
        user.id,
        email: res.email,
        role: res.role,
        isActive: res.isActive,
      );
      setState(() {
        final idx = _users.indexWhere((u) => u.id == updated.id);
        if (idx != -1) _users[idx] = updated;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    }
  }

  Future<void> _toggleActive(User u) async {
    final api = ApiProvider.of(context);
    try {
      final upd = await api.updateUser(u.id, isActive: !(u.isActive ?? true));
      setState(() {
        final idx = _users.indexWhere((e) => e.id == u.id);
        if (idx != -1) _users[idx] = upd;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiProvider.of(context);
    final canManage = api.currentUser?.isSuperAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        actions: [
          IconButton(
            tooltip: _includeInactive
                ? 'Скрыть отключенных'
                : 'Показать отключенных',
            onPressed: () {
              setState(() => _includeInactive = !_includeInactive);
              _load();
            },
            icon: Icon(
              _includeInactive ? Icons.visibility : Icons.visibility_off,
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (canManage)
            IconButton(onPressed: _create, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _users.isEmpty
          ? const Center(child: Text('Нет пользователей'))
          : ListView.separated(
              itemCount: _users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final u = _users[i];
                final inactive = !(u.isActive ?? true);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: inactive
                        ? Colors.grey[300]
                        : Colors.blue[100],
                    child: Text(
                      u.id.toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(
                    '${u.username} • ${u.role}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: inactive ? Colors.grey : const Color(0xFF1F2430),
                    ),
                  ),
                  subtitle: Text(
                    u.email,
                    style: TextStyle(
                      fontSize: 12,
                      color: inactive ? Colors.grey : const Color(0xFF64748B),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canManage)
                        IconButton(
                          tooltip: 'Редактировать',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(u),
                        ),
                      if (canManage)
                        IconButton(
                          tooltip: inactive ? 'Активировать' : 'Деактивировать',
                          icon: Icon(
                            inactive ? Icons.restart_alt : Icons.block,
                          ),
                          onPressed: () => _toggleActive(u),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _UserDraft {
  final String username;
  final String email;
  final String role;
  final String? password; // only for create
  final bool? isActive;
  _UserDraft({
    required this.username,
    required this.email,
    required this.role,
    this.password,
    this.isActive,
  });
}

class _UserDialog extends StatefulWidget {
  final User? existing;
  const _UserDialog({this.existing});
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _passwordCtrl;
  String _role = 'admin';
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _passwordCtrl = TextEditingController();
    _role = e?.role ?? 'admin';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEdit ? 'Редактировать пользователя' : 'Создать пользователя',
      ),
      content: Form(
        key: _form,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(labelText: 'username'),
                  readOnly: isEdit,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'email'),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'email' : null,
                ),
                const SizedBox(height: 12),
                if (!isEdit)
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(labelText: 'password'),
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'min 6' : null,
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('admin')),
                    DropdownMenuItem(
                      value: 'superadmin',
                      child: Text('superadmin'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                  decoration: const InputDecoration(labelText: 'role'),
                ),
                if (isEdit)
                  SwitchListTile(
                    title: const Text('Активен'),
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
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
            final draft = _UserDraft(
              username: _usernameCtrl.text.trim(),
              email: _emailCtrl.text.trim(),
              role: _role,
              password: _passwordCtrl.text.isNotEmpty
                  ? _passwordCtrl.text.trim()
                  : null,
              isActive: _isActive,
            );
            Navigator.pop(context, draft);
          },
          child: Text(isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
