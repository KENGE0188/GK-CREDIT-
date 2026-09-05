import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GKCreditApp());
}

const Color purple = Color(0xFF5B2BEF);
const Color yellow = Color(0xFFFFB800);
const Color green = Color(0xFF20CC71);
const Color red = Color(0xFFEF4444);

String fc(num n) =>
    '${NumberFormat('#,##0', 'fr_FR').format(n)} FC';

String ds(DateTime d) =>
    DateFormat('dd/MM/yyyy').format(d);

class DB {
  static final DB i = DB._();

  DB._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;

    final p = path.join(
      await getDatabasesPath(),
      'gk_credit.db',
    );

    _db = await openDatabase(
      p,
      version: 1,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE users('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'username TEXT UNIQUE, '
          'password TEXT, '
          'name TEXT)',
        );

        await d.execute(
          'CREATE TABLE clients('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT, '
          'phone TEXT, '
          'address TEXT, '
          'note TEXT, '
          'createdAt TEXT)',
        );

        await d.execute(
          'CREATE TABLE articles('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT, '
          'category TEXT, '
          'buyPrice REAL, '
          'sellPrice REAL, '
          'stock INTEGER, '
          'description TEXT)',
        );

        await d.execute(
          'CREATE TABLE sales('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'clientId INTEGER, '
          'articleId INTEGER, '
          'qty INTEGER, '
          'total REAL, '
          'dueDate TEXT, '
          'createdAt TEXT)',
        );

        await d.execute(
          'CREATE TABLE payments('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'saleId INTEGER, '
          'clientId INTEGER, '
          'amount REAL, '
          'date TEXT, '
          'mode TEXT, '
          'reference TEXT, '
          'note TEXT)',
        );

        await d.insert(
          'users',
          {
            'username': 'admin',
            'password': '1234',
            'name': 'Administrateur',
          },
        );
      },
    );

    return _db!;
  }

  Future<List<Map<String, dynamic>>> q(
    String table, {
    String? orderBy,
  }) async {
    return (await db).query(
      table,
      orderBy: orderBy,
    );
  }

  Future<int> add(
    String table,
    Map<String, dynamic> values,
  ) async {
    return (await db).insert(table, values);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values,
    int id,
  ) async {
    return (await db).update(
      table,
      values,
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<int> del(
    String table,
    int id,
  ) async {
    return (await db).delete(
      table,
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> login(
    String username,
    String password,
  ) async {
    final result = await (await db).query(
      'users',
      where: 'username=? AND password=?',
      whereArgs: [username, password],
    );

    return result.isEmpty ? null : result.first;
  }

  Future<double> paid(int saleId) async {
    final result = await (await db).rawQuery(
      'SELECT COALESCE(SUM(amount),0) x '
      'FROM payments WHERE saleId=?',
      [saleId],
    );

    return (result.first['x'] as num).toDouble();
  }

  Future<double> debt() async {
    final sales = await (await db).rawQuery(
      'SELECT COALESCE(SUM(total),0) x FROM sales',
    );

    final payments = await (await db).rawQuery(
      'SELECT COALESCE(SUM(amount),0) x FROM payments',
    );

    return (sales.first['x'] as num).toDouble() -
        (payments.first['x'] as num).toDouble();
  }

  Future<void> backup(String filePath) async {
    final data = <String, dynamic>{};

    for (final table in [
      'users',
      'clients',
      'articles',
      'sales',
      'payments',
    ]) {
      data[table] = await q(table);
    }

    await File(filePath).writeAsString(
      jsonEncode(data),
    );
  }
}

class GKCreditApp extends StatelessWidget {
  const GKCreditApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GK Crédit',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SessionGate(),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  bool loading = true;
  bool logged = false;

  @override
  void initState() {
    super.initState();

    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;

      setState(() {
        logged = prefs.getBool('logged') ?? false;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return logged ? const Home() : const Login();
  }
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController(text: '1234');

  bool hide = true;
  bool busy = false;

  Future<void> go() async {
    setState(() {
      busy = true;
    });

    final result = await DB.i.login(
      username.text.trim(),
      password.text,
    );

    if (!mounted) return;

    setState(() {
      busy = false;
    });

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identifiants incorrects'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('logged', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const Home(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                Container(
                  height: 110,
                  width: 110,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: purple,
                    borderRadius:
                        BorderRadius.circular(28),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GK',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'CRÉDIT',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: yellow,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  'Bienvenue !',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Connectez-vous pour continuer',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Nom d’utilisateur',
                    prefixIcon:
                        Icon(Icons.person_outline),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: password,
                  obscureText: hide,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon:
                        const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hide
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          hide = !hide;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: busy ? null : go,
                  child: busy
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                      : const Text('SE CONNECTER'),
                ),

                const SizedBox(height: 16),

                const Text(
                  'Compte initial : admin / 1234',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  int tick = 0;

  void refresh() {
    setState(() {
      tick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(
        key: ValueKey(tick),
        refresh: refresh,
      ),
      Clients(
        key: ValueKey('c$tick'),
      ),
      Articles(
        key: ValueKey('a$tick'),
      ),
      Sales(
        key: ValueKey('s$tick'),
        refresh: refresh,
      ),
      Reports(
        key: ValueKey('r$tick'),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: pages[tab],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          setState(() {
            tab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon:
                Icon(Icons.inventory_2),
            label: 'Articles',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon:
                Icon(Icons.credit_card),
            label: 'Ventes',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon:
                Icon(Icons.bar_chart),
            label: 'Rapports',
          ),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final VoidCallback refresh;

  const Dashboard({
    super.key,
    required this.refresh,
  });

  Future<Map<String, dynamic>> stats() async {
    final clients = await DB.i.q('clients');
    final sales = await DB.i.q('sales');
    final payments = await DB.i.q('payments');

    final debt = await DB.i.debt();

    final total = sales.fold<double>(
      0,
      (sum, item) =>
          sum + (item['total'] as num).toDouble(),
    );

    final paid = payments.fold<double>(
      0,
      (sum, item) =>
          sum + (item['amount'] as num).toDouble(),
    );

    int due = 0;

    for (final sale in sales) {
      final dueDate =
          sale['dueDate']?.toString() ?? '';

      final today = DateTime.now()
          .toIso8601String()
          .substring(0, 10);

      if (dueDate.compareTo(today) <= 0 &&
          (sale['total'] as num).toDouble() >
              await DB.i.paid(
                sale['id'] as int,
              )) {
        due++;
      }
    }

    return {
      'c': clients.length,
      'd': debt,
      't': total,
      'p': paid,
      'due': due,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: stats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final data = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Bonjour, Gédéon 👋',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Voici un aperçu de votre activité',
            ),

            const SizedBox(height: 16),

            Metric(
              title: 'DETTE TOTALE',
              value: fc(data['d']),
              icon:
                  Icons.account_balance_wallet,
              color: red,
            ),

            const SizedBox(height: 10),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.55,
              children: [
                Metric(
                  title: 'CLIENTS',
                  value: '${data['c']}',
                  icon: Icons.people,
                  color: purple,
                ),
                Metric(
                  title: 'PAIEMENTS',
                  value: fc(data['p']),
                  icon: Icons.payments,
                  color: green,
                ),
                Metric(
                  title: 'VENTES À CRÉDIT',
                  value: fc(data['t']),
                  icon: Icons.credit_card,
                  color: purple,
                ),
                Metric(
                  title: 'ÉCHÉANCES',
                  value: '${data['due']} à suivre',
                  icon: Icons.calendar_today,
                  color: yellow,
                ),
              ],
            ),

            const SizedBox(height: 12),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                padding: const EdgeInsets.all(16),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const SaleForm(),
                  ),
                ).then((_) => refresh());
              },
              icon: const Icon(Icons.add),
              label: const Text(
                'NOUVELLE VENTE À CRÉDIT',
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const DuePage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.event),
                    label: const Text('Échéances'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const SettingsPage(),
                        ),
                      );
                    },
                    icon:
                        const Icon(Icons.settings),
                    label:
                        const Text('Paramètres'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class Metric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const Metric({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: color,
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Clients extends StatefulWidget {
  const Clients({super.key});

  @override
  State<Clients> createState() =>
      _ClientsState();
}

class _ClientsState extends State<Clients> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          FloatingActionButton(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ClientForm(),
            ),
          ).then((_) => setState(() {}));
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: DB.i.q(
          'clients',
          orderBy: 'name',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final rows = snapshot.data!
              .where(
                (item) =>
                    (item['name'] as String)
                        .toLowerCase()
                        .contains(
                          search.toLowerCase(),
                        ),
              )
              .toList();

          return ListView(
            padding:
                const EdgeInsets.all(16),
            children: [
              const Text(
                'Clients',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                onChanged: (value) {
                  setState(() {
                    search = value;
                  });
                },
                decoration:
                    const InputDecoration(
                  prefixIcon:
                      Icon(Icons.search),
                  hintText:
                      'Rechercher un client',
                ),
              ),

              const SizedBox(height: 10),

              ...rows.map(
                (item) => Card(
                  child: ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ClientDetail(
                            id: item['id'] as int,
                          ),
                        ),
                      );
                    },
                    leading: CircleAvatar(
                      backgroundColor: purple,
                      foregroundColor:
                          Colors.white,
                      child: Text(
                        initials(
                          item['name']
                              as String,
                        ),
                      ),
                    ),
                    title:
                        Text(item['name']),
                    subtitle: Text(
                      item['phone'] ?? '',
                    ),
                    trailing:
                        const Icon(
                      Icons.chevron_right,
                    ),
                  ),
                ),
              ),

              if (rows.isEmpty)
                const Padding(
                  padding:
                      EdgeInsets.all(30),
                  child: Center(
                    child:
                        Text('Aucun client'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String initials(String name) {
  return name
      .split(' ')
      .where((item) => item.isNotEmpty)
      .take(2)
      .map((item) => item[0])
      .join()
      .toUpperCase();
}

class ClientForm extends StatefulWidget {
  const ClientForm({super.key});

  @override
  State<ClientForm> createState() =>
      _ClientFormState();
}

class _ClientFormState
    extends State<ClientForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final note = TextEditingController();

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      return;
    }

    await DB.i.add(
      'clients',
      {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'note': note.text.trim(),
        'createdAt':
            DateTime.now().toIso8601String(),
      },
    );

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Ajouter un client'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          Field(
            controller: name,
            label: 'Nom complet',
          ),
          Field(
            controller: phone,
            label: 'Téléphone',
            type: TextInputType.phone,
          ),
          Field(
            controller: address,
            label: 'Adresse',
          ),
          Field(
            controller: note,
            label: 'Note',
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: save,
            child:
                const Text('ENREGISTRER'),
          ),
        ],
      ),
    );
  }
}

class ClientDetail extends StatelessWidget {
  final int id;

  const ClientDetail({
    super.key,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DB.i.q('clients'),
      builder: (context, clientSnapshot) {
        if (!clientSnapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final client = clientSnapshot.data!
            .firstWhere(
              (item) => item['id'] == id,
            );

        return FutureBuilder(
          future: DB.i.q('sales'),
          builder: (context, salesSnapshot) {
            if (!salesSnapshot.hasData) {
              return const Scaffold(
                body: Center(
                  child:
                      CircularProgressIndicator(),
                ),
              );
            }

            final sales = salesSnapshot.data!
                .where(
                  (item) =>
                      item['clientId'] == id,
                )
                .toList();

            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Détails du client',
                ),
              ),
              body: FutureBuilder(
                future: Future.wait(
                  sales.map(
                    (item) => DB.i.paid(
                      item['id'] as int,
                    ),
                  ),
                ),
                builder:
                    (context, paymentSnapshot) {
                  final total =
                      sales.fold<double>(
                    0,
                    (sum, item) =>
                        sum +
                        (item['total'] as num)
                            .toDouble(),
                  );

                  double paid = 0;

                  if (paymentSnapshot
                      .hasData) {
                    paid =
                        paymentSnapshot.data!
                            .fold<double>(
                      0,
                      (sum, value) =>
                          sum + value,
                    );
                  }

                  return ListView(
                    padding:
                        const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor:
                                    purple,
                                foregroundColor:
                                    Colors.white,
                                child: Text(
                                  initials(
                                    client['name']
                                        as String,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                  height: 10),
                              Text(
                                client['name'],
                                style:
                                    const TextStyle(
                                  fontSize: 23,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              Text(
                                '☎ ${client['phone'] ?? ''}',
                              ),
                              Text(
                                '📍 ${client['address'] ?? ''}',
                              ),
                            ],
                          ),
                        ),
                      ),

                      Row(
                        children: [
                          Expanded(
                            child: Metric(
                              title: 'DETTE',
                              value: fc(
                                total - paid,
                              ),
                              icon:
                                  Icons.warning,
                              color: red,
                            ),
                          ),
                          Expanded(
                            child: Metric(
                              title: 'PAYÉ',
                              value: fc(paid),
                              icon: Icons
                                  .check_circle,
                              color: green,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Ventes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      ...sales.map(
                        (sale) => Card(
                          child: ListTile(
                            title: Text(
                              'Vente #${sale['id']}',
                            ),
                            subtitle: Text(
                              'Échéance : ${sale['dueDate']}',
                            ),
                            trailing: Text(
                              fc(sale['total']),
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class Articles extends StatefulWidget {
  const Articles({super.key});

  @override
  State<Articles> createState() =>
      _ArticlesState();
}

class _ArticlesState
    extends State<Articles> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          FloatingActionButton(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ArticleForm(),
            ),
          ).then((_) => setState(() {}));
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: DB.i.q(
          'articles',
          orderBy: 'name',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return ListView(
            padding:
                const EdgeInsets.all(16),
            children: [
              const Text(
                'Articles',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              ...snapshot.data!.map(
                (item) => Card(
                  child: ListTile(
                    leading:
                        const CircleAvatar(
                      child: Icon(
                        Icons.inventory_2,
                      ),
                    ),
                    title:
                        Text(item['name']),
                    subtitle: Text(
                      'Stock : ${item['stock']}',
                    ),
                    trailing: Text(
                      fc(item['sellPrice']),
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ArticleForm extends StatefulWidget {
  const ArticleForm({super.key});

  @override
  State<ArticleForm> createState() =>
      _ArticleFormState();
}

class _ArticleFormState
    extends State<ArticleForm> {
  final name = TextEditingController();
  final category = TextEditingController();
  final buy = TextEditingController();
  final sell = TextEditingController();
  final stock =
      TextEditingController(text: '0');
  final description =
      TextEditingController();

  Future<void> save() async {
    if (name.text.isEmpty ||
        sell.text.isEmpty) {
      return;
    }

    await DB.i.add(
      'articles',
      {
        'name': name.text,
        'category': category.text,
        'buyPrice':
            double.tryParse(buy.text) ?? 0,
        'sellPrice':
            double.tryParse(sell.text) ?? 0,
        'stock':
            int.tryParse(stock.text) ?? 0,
        'description':
            description.text,
      },
    );

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Ajouter un article'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          Field(
            controller: name,
            label: 'Nom de l’article',
          ),
          Field(
            controller: category,
            label: 'Catégorie',
          ),
          Row(
            children: [
              Expanded(
                child: Field(
                  controller: buy,
                  label: 'Prix d’achat',
                  type:
                      TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Field(
                  controller: sell,
                  label: 'Prix de vente',
                  type:
                      TextInputType.number,
                ),
              ),
            ],
          ),
          Field(
            controller: stock,
            label: 'Stock',
            type: TextInputType.number,
          ),
          Field(
            controller: description,
            label: 'Description',
          ),
          FilledButton(
            onPressed: save,
            child:
                const Text('ENREGISTRER'),
          ),
        ],
      ),
    );
  }
}

class Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? type;

  const Field({
    super.key,
    required this.controller,
    required this.label,
    this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}

class SaleForm extends StatefulWidget {
  const SaleForm({super.key});

  @override
  State<SaleForm> createState() =>
      _SaleFormState();
}

class _SaleFormState
    extends State<SaleForm> {
  int? clientId;
  int? articleId;

  final quantity =
      TextEditingController(text: '1');

  final advance =
      TextEditingController(text: '0');

  DateTime due =
      DateTime.now().add(
    const Duration(days: 30),
  );

  Future<void> save() async {
    if (clientId == null ||
        articleId == null) {
      return;
    }

    final articles =
        await DB.i.q('articles');

    final article = articles.firstWhere(
      (item) =>
          item['id'] == articleId,
    );

    final qty =
        int.tryParse(quantity.text) ?? 1;

    final total =
        (article['sellPrice'] as num)
                .toDouble() *
            qty;

    final stock =
        (article['stock'] as num).toInt();

    if (qty <= 0 || qty > stock) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Stock insuffisant'),
        ),
      );

      return;
    }

    final sale = {
      'clientId': clientId,
      'articleId': articleId,
      'qty': qty,
      'total': total,
      'dueDate': due
          .toIso8601String()
          .substring(0, 10),
      'createdAt':
          DateTime.now().toIso8601String(),
    };

    final saleId =
        await DB.i.add('sales', sale);

    await DB.i.update(
      'articles',
      {
        'stock': stock - qty,
      },
      articleId!,
    );

    final adv =
        double.tryParse(advance.text) ?? 0;

    if (adv > 0 && adv <= total) {
      await DB.i.add(
        'payments',
        {
          'saleId': saleId,
          'clientId': clientId,
          'amount': adv,
          'date':
              DateTime.now().toIso8601String(),
          'mode': 'Cash',
          'reference': 'Avance',
          'note': '',
        },
      );
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptPage(
          saleId: saleId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        DB.i.q(
          'clients',
          orderBy: 'name',
        ),
        DB.i.q(
          'articles',
          orderBy: 'name',
        ),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        final clients = snapshot.data![0];
        final articles = snapshot.data![1];

        double total = 0;

        if (articleId != null) {
          final article =
              articles.firstWhere(
            (item) =>
                item['id'] == articleId,
          );

          total =
              (article['sellPrice'] as num)
                      .toDouble() *
                  (int.tryParse(
                        quantity.text,
                      ) ??
                      1);
        }

        final remaining =
            (total -
                    (double.tryParse(
                          advance.text,
                        ) ??
                        0))
                .clamp(
          0,
          double.infinity,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Nouvelle vente à crédit',
            ),
          ),
          body: ListView(
            padding:
                const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<int>(
                initialValue: clientId,
                decoration:
                    const InputDecoration(
                  labelText: 'Client',
                ),
                items: clients
                    .map(
                      (item) =>
                          DropdownMenuItem<int>(
                        value:
                            item['id'] as int,
                        child: Text(
                          item['name'],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    clientId = value;
                  });
                },
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                initialValue: articleId,
                decoration:
                    const InputDecoration(
                  labelText: 'Article',
                ),
                items: articles
                    .map(
                      (item) =>
                          DropdownMenuItem<int>(
                        value:
                            item['id'] as int,
                        child: Text(
                          '${item['name']} (${item['stock']})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    articleId = value;
                  });
                },
              ),

              const SizedBox(height: 10),

              Field(
                controller: quantity,
                label: 'Quantité',
                type: TextInputType.number,
              ),

              Field(
                controller: advance,
                label: 'Avance',
                type: TextInputType.number,
              ),

              ListTile(
                shape:
                    RoundedRectangleBorder(
                  side:
                      const BorderSide(
                    color: Colors.grey,
                  ),
                  borderRadius:
                      BorderRadius.circular(5),
                ),
                title: const Text(
                  'Date d’échéance',
                ),
                subtitle: Text(ds(due)),
                trailing: const Icon(
                  Icons.calendar_today,
                ),
                onTap: () async {
                  final selected =
                      await showDatePicker(
                    context: context,
                    firstDate:
                        DateTime.now(),
                    lastDate:
                        DateTime(2035),
                    initialDate: due,
                  );

                  if (selected != null) {
                    setState(() {
                      due = selected;
                    });
                  }
                },
              ),

              Card(
                color:
                    const Color(0xFFF6F2FF),
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total : ${fc(total)}',
                        style:
                            const TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Reste à payer : ${fc(remaining)}',
                        style:
                            const TextStyle(
                          color: red,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              FilledButton(
                onPressed: save,
                child: const Text(
                  'CONFIRMER LA VENTE',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class Sales extends StatefulWidget {
  final VoidCallback refresh;

  const Sales({
    super.key,
    required this.refresh,
  });

  @override
  State<Sales> createState() =>
      _SalesState();
}

class _SalesState extends State<Sales> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DB.i.q(
        'sales',
        orderBy: 'id DESC',
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        return ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            const Text(
              'Ventes à crédit',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            ...snapshot.data!.map(
              (sale) => FutureBuilder(
                future: Future.wait([
                  DB.i.q('clients'),
                  DB.i.q('articles'),
                  DB.i.paid(
                    sale['id'] as int,
                  ),
                ]),
                builder:
                    (context, result) {
                  if (!result.hasData) {
                    return const SizedBox();
                  }

                  final clients =
                      result.data![0];

                  final articles =
                      result.data![1];

                  final paid =
                      result.data![2]
                          as double;

                  final client =
                      clients.firstWhere(
                    (item) =>
                        item['id'] ==
                        sale['clientId'],
                  );

                  final article =
                      articles.firstWhere(
                    (item) =>
                        item['id'] ==
                        sale['articleId'],
                  );

                  final remaining =
                      (sale['total'] as num)
                              .toDouble() -
                          paid;

                  return Card(
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ReceiptPage(
                              saleId:
                                  sale['id']
                                      as int,
                            ),
                          ),
                        ).then(
                          (_) => setState(
                            () {},
                          ),
                        );
                      },
                      title: Text(
                        client['name'],
                      ),
                      subtitle: Text(
                        '${article['name']} · Échéance ${sale['dueDate']}',
                      ),
                      trailing: Column(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .end,
                        children: [
                          Text(
                            fc(sale['total']),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Reste ${fc(remaining)}',
                            style: TextStyle(
                              color: remaining >
                                      0
                                  ? red
                                  : green,
                              fontSize: 11,
                            ),
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
      },
    );
  }
}

class DuePage extends StatelessWidget {
  const DuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DB.i.q(
        'sales',
        orderBy: 'dueDate',
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final today = DateTime.now()
            .toIso8601String()
            .substring(0, 10);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Échéances'),
          ),
          body: ListView(
            padding:
                const EdgeInsets.all(16),
            children: snapshot.data!
                .map(
                  (sale) => FutureBuilder(
                    future: Future.wait([
                      DB.i.q('clients'),
                      DB.i.paid(
                        sale['id'] as int,
                      ),
                    ]),
                    builder:
                        (context, result) {
                      if (!result.hasData) {
                        return const SizedBox();
                      }

                      final clients =
                          result.data![0];

                      final paid =
                          result.data![1]
                              as double;

                      final remaining =
                          (sale['total'] as num)
                                  .toDouble() -
                              paid;

                      if (remaining <= 0) {
                        return const SizedBox();
                      }

                      final client =
                          clients.firstWhere(
                        (item) =>
                            item['id'] ==
                            sale['clientId'],
                      );

                      final late =
                          (sale['dueDate']
                                  as String)
                              .compareTo(today) <
                              0;

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                late
                                    ? red
                                    : yellow,
                            child: Icon(
                              late
                                  ? Icons.warning
                                  : Icons.event,
                              color:
                                  Colors.white,
                            ),
                          ),
                          title: Text(
                            client['name'],
                          ),
                          subtitle: Text(
                            'Échéance : ${sale['dueDate']}',
                          ),
                          trailing: Text(
                            fc(remaining),
                            style: TextStyle(
                              color: late
                                  ? red
                                  : Colors.black,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class Reports extends StatelessWidget {
  const Reports({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        DB.i.q('sales'),
        DB.i.q('payments'),
        DB.i.debt(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final sales =
            snapshot.data![0];

        final payments =
            snapshot.data![1];

        final debt =
            snapshot.data![2] as double;

        final total =
            sales.fold<double>(
          0,
          (sum, item) =>
              sum +
              (item['total'] as num)
                  .toDouble(),
        );

        final paid =
            payments.fold<double>(
          0,
          (sum, item) =>
              sum +
              (item['amount'] as num)
                  .toDouble(),
        );

        return ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            const Text(
              'Rapports',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              children: [
                Metric(
                  title: 'VENTES TOTALES',
                  value: fc(total),
                  icon:
                      Icons.shopping_cart,
                  color: purple,
                ),
                Metric(
                  title: 'PAIEMENTS REÇUS',
                  value: fc(paid),
                  icon: Icons.payments,
                  color: green,
                ),
                Metric(
                  title: 'DETTES RESTANTES',
                  value: fc(debt),
                  icon: Icons.warning,
                  color: red,
                ),
                Metric(
                  title: 'NOMBRE DE VENTES',
                  value:
                      '${sales.length}',
                  icon:
                      Icons.receipt_long,
                  color: yellow,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class ReceiptPage extends StatelessWidget {
  final int saleId;

  const ReceiptPage({
    super.key,
    required this.saleId,
  });

  Future<Uint8List> generatePdf() async {
    final sales =
        await DB.i.q('sales');

    final sale = sales.firstWhere(
      (item) =>
          item['id'] == saleId,
    );

    final clients =
        await DB.i.q('clients');

    final articles =
        await DB.i.q('articles');

    final client =
        clients.firstWhere(
      (item) =>
          item['id'] ==
          sale['clientId'],
    );

    final article =
        articles.firstWhere(
      (item) =>
          item['id'] ==
          sale['articleId'],
    );

    final paid =
        await DB.i.paid(saleId);

    final document = pw.Document();

    document.addPage(
      pw.Page(
        build: (pdfContext) {
          return pw.Center(
            child: pw.Column(
              crossAxisAlignment:
                  pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'GK CRÉDIT',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Gestion des ventes à crédit',
                ),
                pw.Divider(),
                pw.Text(
                  'Client : ${client['name']}',
                ),
                pw.Text(
                  'Article : ${article['name']}',
                ),
                pw.Text(
                  'Quantité : ${sale['qty']}',
                ),
                pw.Text(
                  'Total : ${fc(sale['total'])}',
                ),
                pw.Text(
                  'Payé : ${fc(paid)}',
                ),
                pw.Text(
                  'Reste : ${fc((sale['total'] as num).toDouble() - paid)}',
                ),
                pw.Text(
                  'Échéance : ${sale['dueDate']}',
                ),
                pw.Divider(),
                pw.Text(
                  'Merci pour votre confiance !',
                ),
              ],
            ),
          );
        },
      ),
    );

    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DB.i.q('sales'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final sale =
            snapshot.data!.firstWhere(
          (item) =>
              item['id'] == saleId,
        );

        return Scaffold(
          appBar: AppBar(
            title:
                const Text('Reçu de vente'),
          ),
          body: FutureBuilder(
            future: Future.wait([
              DB.i.q('clients'),
              DB.i.q('articles'),
              DB.i.paid(saleId),
            ]),
            builder:
                (context, result) {
              if (!result.hasData) {
                return const Center(
                  child:
                      CircularProgressIndicator(),
                );
              }

              final clients =
                  result.data![0];

              final articles =
                  result.data![1];

              final paid =
                  result.data![2]
                      as double;

              final client =
                  clients.firstWhere(
                (item) =>
                    item['id'] ==
                    sale['clientId'],
              );

              final article =
                  articles.firstWhere(
                (item) =>
                    item['id'] ==
                    sale['articleId'],
              );

              final remaining =
                  (sale['total'] as num)
                          .toDouble() -
                      paid;

              return ListView(
                padding:
                    const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        22,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Center(
                            child: Text(
                              'GK CRÉDIT',
                              style:
                                  TextStyle(
                                fontSize: 25,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          const Center(
                            child: Text(
                              'Gestion des ventes à crédit',
                            ),
                          ),
                          const Divider(
                            height: 28,
                          ),
                          Text(
                            'Client : ${client['name']}',
                          ),
                          Text(
                            'Article : ${article['name']}',
                          ),
                          Text(
                            'Quantité : ${sale['qty']}',
                          ),
                          const Divider(),
                          Text(
                            'Montant total : ${fc(sale['total'])}',
                          ),
                          Text(
                            'Total payé : ${fc(paid)}',
                          ),
                          Text(
                            'Reste à payer : ${fc(remaining)}',
                            style:
                                const TextStyle(
                              color: red,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Échéance : ${sale['dueDate']}',
                          ),
                          const Divider(),
                          const Center(
                            child: Text(
                              'Merci pour votre confiance !',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  FilledButton.icon(
                    onPressed: () async {
                      await Printing.layoutPdf(
                        onLayout:
                            (format) =>
                                generatePdf(),
                      );
                    },
                    icon: const Icon(
                      Icons.print,
                    ),
                    label: const Text(
                      'IMPRIMER / PDF',
                    ),
                  ),

                  OutlinedButton.icon(
                    onPressed: () async {
                      final bytes =
                          await generatePdf();

                      await Share
                          .shareXFiles(
                        [
                          XFile.fromData(
                            bytes,
                            name:
                                'recu_gk_credit_$saleId.pdf',
                            mimeType:
                                'application/pdf',
                          ),
                        ],
                      );
                    },
                    icon: const Icon(
                      Icons.share,
                    ),
                    label: const Text(
                      'PARTAGER LE REÇU',
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class SettingsPage
    extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> logout(
    BuildContext context,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.remove('logged');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const Login(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Paramètres'),
      ),
      body: ListView(
        children: [
          const ListTile(
            leading:
                Icon(Icons.business),
            title: Text(
              'Informations entreprise',
            ),
            subtitle:
                Text('GK CRÉDIT'),
          ),

          const ListTile(
            leading:
                Icon(Icons.storage),
            title:
                Text('Sauvegarde locale'),
            subtitle:
                Text('SQLite activé'),
          ),

          ListTile(
            leading: const Icon(
              Icons.file_download,
            ),
            title: const Text(
              'Exporter une sauvegarde',
            ),
            onTap: () async {
              final filePath =
                  '${await getDatabasesPath()}/gk_credit_backup.json';

              await DB.i.backup(
                filePath,
              );

              if (!context.mounted) {
                return;
              }

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sauvegarde créée : $filePath',
                  ),
                ),
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(
              Icons.logout,
              color: red,
            ),
            title: const Text(
              'Déconnexion',
              style: TextStyle(
                color: red,
              ),
            ),
            onTap: () => logout(
              context,
            ),
          ),
        ],
      ),
    );
  }
}
