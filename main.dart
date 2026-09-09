
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
import 'package:path/path.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GKCreditApp());
}

const Color purple = Color(0xFF5B2BEF);
const Color yellow = Color(0xFFFFB800);
const Color green = Color(0xFF20CC71);
const Color red = Color(0xFFEF4444);

String fc(num n) => '${NumberFormat('#,##0', 'fr_FR').format(n)} FC';
String ds(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

class DB {
  static final DB i = DB._();
  DB._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final p = join(await getDatabasesPath(), 'gk_credit.db');
    _db = await openDatabase(p, version: 1, onCreate: (d, v) async {
      await d.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, password TEXT, name TEXT)');
      await d.execute('CREATE TABLE clients(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, address TEXT, note TEXT, createdAt TEXT)');
      await d.execute('CREATE TABLE articles(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, category TEXT, buyPrice REAL, sellPrice REAL, stock INTEGER, description TEXT)');
      await d.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, clientId INTEGER, articleId INTEGER, qty INTEGER, total REAL, dueDate TEXT, createdAt TEXT)');
      await d.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT, saleId INTEGER, clientId INTEGER, amount REAL, date TEXT, mode TEXT, reference TEXT, note TEXT)');
      await d.insert('users', {'username':'admin','password':'1234','name':'Administrateur'});
    });
    return _db!;
  }

  Future<List<Map<String,dynamic>>> q(String table, {String? orderBy}) async => (await db).query(table, orderBy: orderBy);
  Future<int> add(String table, Map<String,dynamic> v) async => (await db).insert(table, v);
  Future<int> update(String table, Map<String,dynamic> v, int id) async => (await db).update(table,v,where:'id=?',whereArgs:[id]);
  Future<int> del(String table, int id) async => (await db).delete(table,where:'id=?',whereArgs:[id]);

  Future<Map<String,dynamic>?> login(String u,String p) async {
    final r=await (await db).query('users',where:'username=? AND password=?',whereArgs:[u,p]);
    return r.isEmpty?null:r.first;
  }
  Future<double> paid(int saleId) async {
    final r=await (await db).rawQuery('SELECT COALESCE(SUM(amount),0) x FROM payments WHERE saleId=?',[saleId]);
    return (r.first['x'] as num).toDouble();
  }
  Future<double> debt() async {
    final r=await (await db).rawQuery('SELECT COALESCE(SUM(total),0) x FROM sales');
    final p=await (await db).rawQuery('SELECT COALESCE(SUM(amount),0) x FROM payments');
    return (r.first['x'] as num).toDouble()-(p.first['x'] as num).toDouble();
  }
  Future<void> backup(String path) async {
    final data=<String,dynamic>{};
    for(final t in ['users','clients','articles','sales','payments']) data[t]=await q(t);
    await File(path).writeAsString(jsonEncode(data));
  }
}

class GKCreditApp extends StatelessWidget {
  const GKCreditApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'GK Crédit',
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:purple),
      inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder())),
    home:const SessionGate(),
  );
}

class SessionGate extends StatefulWidget { const SessionGate({super.key}); @override State<SessionGate> createState()=>_SessionGateState(); }
class _SessionGateState extends State<SessionGate>{
  bool loading=true, logged=false;
  @override void initState(){super.initState(); SharedPreferences.getInstance().then((p){setState((){logged=p.getBool('logged')??false;loading=false;});});}
  @override Widget build(BuildContext c)=>loading?const Scaffold(body:Center(child:CircularProgressIndicator())):logged?const Home():const Login();
}

class Login extends StatefulWidget { const Login({super.key}); @override State<Login> createState()=>_LoginState(); }
class _LoginState extends State<Login>{
  final u=TextEditingController(text:'admin'), p=TextEditingController(text:'1234');
  bool hide=true, busy=false;
  Future<void> go() async {
    setState(()=>busy=true);
    final x=await DB.i.login(u.text.trim(),p.text);
    setState(()=>busy=false);
    if(x==null){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Identifiants incorrects'))); return; }
    final sp=await SharedPreferences.getInstance(); await sp.setBool('logged',true);
    if(mounted) Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Home()));
  }
  @override Widget build(BuildContext c)=>Scaffold(
    body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const SizedBox(height:40),
        Container(height:110,width:110,alignment:Alignment.center,decoration:BoxDecoration(color:purple,borderRadius:BorderRadius.circular(28)),child:const Column(mainAxisSize:MainAxisSize.min,children:[Text('GK',style:TextStyle(fontSize:42,fontWeight:FontWeight.w900,color:Colors.white)),Text('CRÉDIT',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold,color:yellow))])),
        const SizedBox(height:28),const Text('Bienvenue !',textAlign:TextAlign.center,style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),const Text('Connectez-vous pour continuer',textAlign:TextAlign.center),
        const SizedBox(height:28),
        TextField(controller:u,decoration:const InputDecoration(labelText:'Nom d’utilisateur',prefixIcon:Icon(Icons.person_outline))),
        const SizedBox(height:12),
        TextField(controller:p,obscureText:hide,decoration:InputDecoration(labelText:'Mot de passe',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(icon:Icon(hide?Icons.visibility:Icons.visibility_off),onPressed:()=>setState(()=>hide=!hide))),
        const SizedBox(height:18),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:purple,padding:const EdgeInsets.all(16)),onPressed:busy?null:go,child:busy?const CircularProgressIndicator(color:Colors.white):const Text('SE CONNECTER')),
        const SizedBox(height:16),const Text('Compte initial : admin / 1234',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey,fontSize:12)),
      ]))),
  );
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home>{
  int tab=0; int tick=0;
  void refresh()=>setState(()=>tick++);
  @override Widget build(BuildContext c){
    final pages=[Dashboard(key:ValueKey(tick),refresh:refresh),Clients(key:ValueKey('c$tick')),Articles(key:ValueKey('a$tick')),Sales(key:ValueKey('s$tick'),refresh:refresh),Reports(key:ValueKey('r$tick'))];
    return Scaffold(body:SafeArea(child:pages[tab]),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(x)=>setState(()=>tab=x),destinations:const[
      NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Accueil'),
      NavigationDestination(icon:Icon(Icons.people_outline),selectedIcon:Icon(Icons.people),label:'Clients'),
      NavigationDestination(icon:Icon(Icons.inventory_2_outlined),selectedIcon:Icon(Icons.inventory_2),label:'Articles'),
      NavigationDestination(icon:Icon(Icons.credit_card_outlined),selectedIcon:Icon(Icons.credit_card),label:'Ventes'),
      NavigationDestination(icon:Icon(Icons.bar_chart_outlined),selectedIcon:Icon(Icons.bar_chart),label:'Rapports'),
    ]));
  }
}

class Dashboard extends StatelessWidget{
  final VoidCallback refresh; const Dashboard({super.key,required this.refresh});
  Future<Map<String,dynamic>> stats() async {
    final clients=await DB.i.q('clients'), sales=await DB.i.q('sales'), pays=await DB.i.q('payments');
    final debt=await DB.i.debt(); final total=sales.fold<double>(0,(a,x)=>a+(x['total'] as num).toDouble());
    final paid=pays.fold<double>(0,(a,x)=>a+(x['amount'] as num).toDouble());
    int due=0; for(final s in sales){if((s['dueDate']??'').compareTo(DateTime.now().toIso8601String().substring(0,10))<=0 && (s['total'] as num).toDouble()>await DB.i.paid(s['id'] as int)) due++;}
    return {'c':clients.length,'d':debt,'t':total,'p':paid,'due':due};
  }
  @override Widget build(BuildContext c)=>FutureBuilder(future:stats(),builder:(c,s){
    if(!s.hasData)return const Center(child:CircularProgressIndicator()); final x=s.data!;
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Bonjour, Gédéon 👋',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)),const Text('Voici un aperçu de votre activité'),
      const SizedBox(height:16),Metric(title:'DETTE TOTALE',value:fc(x['d']),icon:Icons.account_balance_wallet,color:red),
      const SizedBox(height:10),GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.55,children:[
        Metric(title:'CLIENTS',value:'${x['c']}',icon:Icons.people,color:purple),
        Metric(title:'PAIEMENTS',value:fc(x['p']),icon:Icons.payments,color:green),
        Metric(title:'VENTES À CRÉDIT',value:fc(x['t']),icon:Icons.credit_card,color:purple),
        Metric(title:'ÉCHÉANCES',value:'${x['due']} à suivre',icon:Icons.calendar_today,color:yellow),
      ]),
      const SizedBox(height:12),
      FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:purple,padding:const EdgeInsets.all(16)),onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const SaleForm())).then((_)=>refresh()),icon:const Icon(Icons.add),label:const Text('NOUVELLE VENTE À CRÉDIT')),
      const SizedBox(height:12),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const DuePage())),icon:const Icon(Icons.event),label:const Text('Échéances'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.settings),label:const Text('Paramètres')))]),
    ]);
  });
}

class Metric extends StatelessWidget{final String title,value;final IconData icon;final Color color;const Metric({super.key,required this.title,required this.value,required this.icon,required this.color});
@override Widget build(BuildContext c)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color),const Spacer(),Text(title,style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold,color:Colors.grey)),Text(value,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800))])));}

class Clients extends StatefulWidget{const Clients({super.key});@override State<Clients> createState()=>_ClientsState();}
class _ClientsState extends State<Clients>{
  String search='';
  @override Widget build(BuildContext c)=>Scaffold(
    floatingActionButton:FloatingActionButton(backgroundColor:purple,foregroundColor:Colors.white,onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const ClientForm())).then((_)=>setState((){})),child:const Icon(Icons.add)),
    body:FutureBuilder(future:DB.i.q('clients',orderBy:'name'),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!.where((x)=>(x['name'] as String).toLowerCase().contains(search.toLowerCase())).toList();return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Clients',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:12),
      TextField(onChanged:(x)=>setState(()=>search=x),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Rechercher un client')),
      const SizedBox(height:10),
      ...rows.map((x)=>Card(child:ListTile(onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>ClientDetail(id:x['id'] as int))),leading:CircleAvatar(backgroundColor:purple,foregroundColor:Colors.white,child:Text(initials(x['name'] as String))),title:Text(x['name']),subtitle:Text(x['phone']??''),trailing:const Icon(Icons.chevron_right)))),
      if(rows.isEmpty)const Padding(padding:EdgeInsets.all(30),child:Center(child:Text('Aucun client'))),
    ]);}));
}

String initials(String n)=>n.split(' ').where((x)=>x.isNotEmpty).take(2).map((x)=>x[0]).join().toUpperCase();

class ClientForm extends StatefulWidget{const ClientForm({super.key});@override State<ClientForm> createState()=>_ClientFormState();}
class _ClientFormState extends State<ClientForm>{final n=TextEditingController(),p=TextEditingController(),a=TextEditingController(),note=TextEditingController();
Future<void> save()async{if(n.text.trim().isEmpty)return;await DB.i.add('clients',{'name':n.text.trim(),'phone':p.text.trim(),'address':a.text.trim(),'note':note.text.trim(),'createdAt':DateTime.now().toIso8601String()});if(mounted)Navigator.pop(context);}
@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Ajouter un client')),body:ListView(padding:const EdgeInsets.all(16),children:[Field(c:n,l:'Nom complet'),Field(c:p,l:'Téléphone',type:TextInputType.phone),Field(c:a,l:'Adresse'),Field(c:note,l:'Note'),const SizedBox(height:10),FilledButton(onPressed:save,child:const Text('ENREGISTRER'))]));}

class ClientDetail extends StatelessWidget{final int id;const ClientDetail({super.key,required this.id});
@override Widget build(BuildContext c)=>FutureBuilder(future:DB.i.q('clients'),builder:(c,sc){if(!sc.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final cl=sc.data!.firstWhere((x)=>x['id']==id);return FutureBuilder(future:DB.i.q('sales'),builder:(c,ss){if(!ss.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final sales=ss.data!.where((x)=>x['clientId']==id).toList();return Scaffold(appBar:AppBar(title:const Text('Détails du client')),body:FutureBuilder(future:Future.wait(sales.map((x)=>DB.i.paid(x['id'] as int))),builder:(c,ps){double total=sales.fold(0,(a,x)=>a+(x['total'] as num).toDouble());double paid=ps.hasData?ps.data!.fold(0,(a,b)=>a+(b as double)):0;return ListView(padding:const EdgeInsets.all(16),children:[
Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[CircleAvatar(radius:28,backgroundColor:purple,foregroundColor:Colors.white,child:Text(initials(cl['name']))),const SizedBox(height:10),Text(cl['name'],style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),Text('☎ ${cl['phone']??''}'),Text('📍 ${cl['address']??''}')])),
Row(children:[Expanded(child:Metric(title:'DETTE',value:fc(total-paid),icon:Icons.warning,color:red)),Expanded(child:Metric(title:'PAYÉ',value:fc(paid),icon:Icons.check_circle,color:green))]),
const SizedBox(height:8),const Text('Ventes',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
...sales.map((s)=>Card(child:ListTile(title:Text('Vente #${s['id']}'),subtitle:Text('Échéance : ${s['dueDate']}'),trailing:Text(fc((s['total'] as num).toDouble()),style:const TextStyle(fontWeight:FontWeight.bold))))),
] );});});});}

class Articles extends StatefulWidget{const Articles({super.key});@override State<Articles> createState()=>_ArticlesState();}
class _ArticlesState extends State<Articles>{@override Widget build(BuildContext c)=>Scaffold(floatingActionButton:FloatingActionButton(backgroundColor:purple,foregroundColor:Colors.white,onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const ArticleForm())).then((_)=>setState((){})),child:const Icon(Icons.add)),body:FutureBuilder(future:DB.i.q('articles',orderBy:'name'),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(16),children:[const Text('Articles',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:12),...s.data!.map((x)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.inventory_2)),title:Text(x['name']),subtitle:Text('Stock : ${x['stock']}'),trailing:Text(fc(x['sellPrice']),style:const TextStyle(fontWeight:FontWeight.bold)))))]);}));}
class ArticleForm extends StatefulWidget{const ArticleForm({super.key});@override State<ArticleForm> createState()=>_ArticleFormState();}
class _ArticleFormState extends State<ArticleForm>{final n=TextEditingController(),cat=TextEditingController(),buy=TextEditingController(),sell=TextEditingController(),stock=TextEditingController(text:'0'),desc=TextEditingController();
Future<void> save()async{if(n.text.isEmpty||sell.text.isEmpty)return;await DB.i.add('articles',{'name':n.text,'category':cat.text,'buyPrice':double.tryParse(buy.text)??0,'sellPrice':double.tryParse(sell.text)??0,'stock':int.tryParse(stock.text)??0,'description':desc.text});if(mounted)Navigator.pop(context);}
@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Ajouter un article')),body:ListView(padding:const EdgeInsets.all(16),children:[Field(c:n,l:'Nom de l’article'),Field(c:cat,l:'Catégorie'),Row(children:[Expanded(child:Field(c:buy,l:'Prix d’achat',type:TextInputType.number)),const SizedBox(width:8),Expanded(child:Field(c:sell,l:'Prix de vente',type:TextInputType.number))]),Field(c:stock,l:'Stock',type:TextInputType.number),Field(c:desc,l:'Description'),FilledButton(onPressed:save,child:const Text('ENREGISTRER'))]));}

class Field extends StatelessWidget{final TextEditingController c;final String l;final TextInputType? type;const Field({super.key,required this.c,required this.l,this.type});
@override Widget build(BuildContext x)=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,keyboardType:type,decoration:InputDecoration(labelText:l)));}

class SaleForm extends StatefulWidget{const SaleForm({super.key});@override State<SaleForm> createState()=>_SaleFormState();}
class _SaleFormState extends State<SaleForm>{
  int? cid,aid; final qty=TextEditingController(text:'1'),advance=TextEditingController(text:'0'); DateTime due=DateTime.now().add(const Duration(days:30));
  Future<void> save()async{if(cid==null||aid==null)return;final a=(await DB.i.q('articles')).firstWhere((x)=>x['id']==aid);final q=int.tryParse(qty.text)??1;final total=(a['sellPrice'] as num).toDouble()*q;if(q<=0||q>(a['stock'] as num).toInt()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Stock insuffisant')));return;}final sale={'clientId':cid,'articleId':aid,'qty':q,'total':total,'dueDate':due.toIso8601String().substring(0,10),'createdAt':DateTime.now().toIso8601String()};final id=await DB.i.add('sales',sale);await DB.i.update('articles',{'stock':(a['stock'] as num).toInt()-q},aid!);final adv=double.tryParse(advance.text)??0;if(adv>0&&adv<=total)await DB.i.add('payments',{'saleId':id,'clientId':cid,'amount':adv,'date':DateTime.now().toIso8601String(),'mode':'Cash','reference':'Avance','note':''});if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>ReceiptPage(saleId:id)));}
  @override Widget build(BuildContext c)=>FutureBuilder(future:Future.wait([DB.i.q('clients',orderBy:'name'),DB.i.q('articles',orderBy:'name')]),builder:(c,s){if(!s.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final clients=s.data![0], arts=s.data![1];double total=aid==null?0:(arts.firstWhere((x)=>x['id']==aid)['sellPrice'] as num).toDouble()*(int.tryParse(qty.text)??1);double rem=(total-(double.tryParse(advance.text)??0)).clamp(0,double.infinity);return Scaffold(appBar:AppBar(title:const Text('Nouvelle vente à crédit')),body:ListView(padding:const EdgeInsets.all(16),children:[
DropdownButtonFormField<int>(value:cid,decoration:const InputDecoration(labelText:'Client'),items:clients.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text(x['name']))).toList(),onChanged:(x)=>setState(()=>cid=x)),const SizedBox(height:10),
DropdownButtonFormField<int>(value:aid,decoration:const InputDecoration(labelText:'Article'),items:arts.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text('${x['name']} (${x['stock']})'))).toList(),onChanged:(x)=>setState(()=>aid=x)),const SizedBox(height:10),
Field(c:qty,l:'Quantité',type:TextInputType.number),Field(c:advance,l:'Avance',type:TextInputType.number),
ListTile(shape:RoundedRectangleBorder(side:const BorderSide(color:Colors.grey),borderRadius:BorderRadius.circular(5)),title:const Text('Date d’échéance'),subtitle:Text(ds(due)),trailing:const Icon(Icons.calendar_today),onTap:()async{final x=await showDatePicker(context:c,firstDate:DateTime.now(),lastDate:DateTime(2035),initialDate:due);if(x!=null)setState(()=>due=x);}),
Card(color:const Color(0xFFF6F2FF),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Total : ${fc(total)}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('Reste à payer : ${fc(rem)}',style:const TextStyle(color:red,fontWeight:FontWeight.bold))])),
FilledButton(onPressed:save,child:const Text('CONFIRMER LA VENTE'))
]));});}
}

class Sales extends StatefulWidget{final VoidCallback refresh;const Sales({super.key,required this.refresh});@override State<Sales> createState()=>_SalesState();}
class _SalesState extends State<Sales>{@override Widget build(BuildContext c)=>FutureBuilder(future:DB.i.q('sales',orderBy:'id DESC'),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(16),children:[const Text('Ventes à crédit',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:10),...s.data!.map((x)=>FutureBuilder(future:Future.wait([DB.i.q('clients'),DB.i.q('articles'),DB.i.paid(x['id'] as int)]),builder:(c,z){if(!z.hasData)return const SizedBox();final cl=z.data![0].firstWhere((q)=>q['id']==x['clientId']);final ar=z.data![1].firstWhere((q)=>q['id']==x['articleId']);final remain=(x['total'] as num).toDouble()-(z.data![2] as double);return Card(child:ListTile(onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>ReceiptPage(saleId:x['id'] as int))).then((_)=>setState((){})),title:Text(cl['name']),subtitle:Text('${ar['name']} · Échéance ${x['dueDate']}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(fc(x['total']),style:const TextStyle(fontWeight:FontWeight.bold)),Text('Reste ${fc(remain)}',style:TextStyle(color:remain>0?red:green,fontSize:11))]))}))]);}));}

class DuePage extends StatelessWidget{const DuePage({super.key});@override Widget build(BuildContext c)=>FutureBuilder(future:DB.i.q('sales',orderBy:'dueDate'),builder:(c,s){if(!s.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final now=DateTime.now().toIso8601String().substring(0,10);return Scaffold(appBar:AppBar(title:const Text('Échéances')),body:ListView(padding:const EdgeInsets.all(16),children:s.data!.map((x)=>FutureBuilder(future:Future.wait([DB.i.q('clients'),DB.i.paid(x['id'] as int)]),builder:(c,z){if(!z.hasData)return const SizedBox();final rem=(x['total'] as num).toDouble()-(z.data![1] as double);if(rem<=0)return const SizedBox();final cl=z.data![0].firstWhere((q)=>q['id']==x['clientId']);final late=(x['dueDate'] as String).compareTo(now)<0;return Card(child:ListTile(leading:CircleAvatar(backgroundColor:late?red:yellow,child:Icon(late?Icons.warning:Icons.event,color:Colors.white)),title:Text(cl['name']),subtitle:Text('Échéance : ${x['dueDate']}'),trailing:Text(fc(rem),style:TextStyle(color:late?red:Colors.black,fontWeight:FontWeight.bold))));})).toList()));});}

class Reports extends StatelessWidget{const Reports({super.key});@override Widget build(BuildContext c)=>FutureBuilder(future:Future.wait([DB.i.q('sales'),DB.i.q('payments'),DB.i.debt()]),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final sales=s.data![0], pays=s.data![1];final total=sales.fold<double>(0,(a,x)=>a+(x['total'] as num).toDouble());final paid=pays.fold<double>(0,(a,x)=>a+(x['amount'] as num).toDouble());return ListView(padding:const EdgeInsets.all(16),children:[const Text('Rapports',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:12),GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),children:[Metric(title:'VENTES TOTALES',value:fc(total),icon:Icons.shopping_cart,color:purple),Metric(title:'PAIEMENTS REÇUS',value:fc(paid),icon:Icons.payments,color:green),Metric(title:'DETTES RESTANTES',value:fc(s.data![2]),icon:Icons.warning,color:red),Metric(title:'NOMBRE DE VENTES',value:'${sales.length}',icon:Icons.receipt_long,color:yellow)])]);});}

class ReceiptPage extends StatelessWidget{final int saleId;const ReceiptPage({super.key,required this.saleId});
Future<Uint8List> pdf()async{final sales=await DB.i.q('sales');final s=sales.firstWhere((x)=>x['id']==saleId);final cl=(await DB.i.q('clients')).firstWhere((x)=>x['id']==s['clientId']);final ar=(await DB.i.q('articles')).firstWhere((x)=>x['id']==s['articleId']);final paid=await DB.i.paid(saleId);final doc=pw.Document();doc.addPage(pw.Page(build:(_)=>pw.Center(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('GK CRÉDIT',style:pw.TextStyle(fontSize:24,fontWeight:pw.FontWeight.bold)),pw.Text('Gestion des ventes à crédit'),pw.Divider(),pw.Text('Client : ${cl['name']}'),pw.Text('Article : ${ar['name']}'),pw.Text('Quantité : ${s['qty']}'),pw.Text('Total : ${fc(s['total'])}'),pw.Text('Payé : ${fc(paid)}'),pw.Text('Reste : ${fc((s['total'] as num).toDouble()-paid)}'),pw.Text('Échéance : ${s['dueDate']}'),pw.Divider(),pw.Text('Merci pour votre confiance !')]))));return doc.save();}
@override Widget build(BuildContext c)=>FutureBuilder(future:DB.i.q('sales'),builder:(c,z){if(!z.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final s=z.data!.firstWhere((x)=>x['id']==saleId);return Scaffold(appBar:AppBar(title:const Text('Reçu de vente')),body:FutureBuilder(future:Future.wait([DB.i.q('clients'),DB.i.q('articles'),DB.i.paid(saleId)]),builder:(c,x){if(!x.hasData)return const Center(child:CircularProgressIndicator());final cl=x.data![0].firstWhere((q)=>q['id']==s['clientId']);final ar=x.data![1].firstWhere((q)=>q['id']==s['articleId']);final paid=x.data![2] as double;final rem=(s['total'] as num).toDouble()-paid;return ListView(padding:const EdgeInsets.all(20),children:[Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Center(child:Text('GK CRÉDIT',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold))),const Center(child:Text('Gestion des ventes à crédit')),const Divider(height:28),Text('Client : ${cl['name']}'),Text('Article : ${ar['name']}'),Text('Quantité : ${s['qty']}'),const Divider(),Text('Montant total : ${fc(s['total'])}'),Text('Total payé : ${fc(paid)}'),Text('Reste à payer : ${fc(rem)}',style:const TextStyle(color:red,fontWeight:FontWeight.bold)),Text('Échéance : ${s['dueDate']}'),const Divider(),const Center(child:Text('Merci pour votre confiance !'))]))),const SizedBox(height:12),FilledButton.icon(onPressed:()async=>Printing.layoutPdf(onLayout:(_)=>pdf()),icon:const Icon(Icons.print),label:const Text('IMPRIMER / PDF')),OutlinedButton.icon(onPressed:()async{final b=await pdf();await Share.shareXFiles([XFile.fromData(b,name:'recu_gk_credit_$saleId.pdf',mimeType:'application/pdf')]);},icon:const Icon(Icons.share),label:const Text('PARTAGER LE REÇU'))]);});});}
}

class SettingsPage extends StatelessWidget{const SettingsPage({super.key});Future<void> logout(BuildContext c)async{final p=await SharedPreferences.getInstance();await p.remove('logged');if(c.mounted)Navigator.pushAndRemoveUntil(c,MaterialPageRoute(builder:(_)=>const Login()),(_)=>false);}
@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Paramètres')),body:ListView(children:[ListTile(leading:const Icon(Icons.business),title:const Text('Informations entreprise'),subtitle:const Text('GK CRÉDIT')),ListTile(leading:const Icon(Icons.storage),title:const Text('Sauvegarde locale'),subtitle:const Text('SQLite activé')),ListTile(leading:const Icon(Icons.file_download),title:const Text('Exporter une sauvegarde'),onTap:()async{final path='${(await getDatabasesPath())}/gk_credit_backup.json';await DB.i.backup(path);if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('Sauvegarde créée : $path')));}),const Divider(),ListTile(leading:const Icon(Icons.logout,color:red),title:const Text('Déconnexion',style:TextStyle(color:red)),onTap:()=>logout(c))]));}
