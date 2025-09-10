/*
Crypto & Fiat Converter Flutter App
Single-file example: main.dart

Features implemented:
- Two tabs: Crypto and Fiat
- Fetches current prices from CoinGecko (simple/price and coins/list)
- Search with incremental uppercase matching (type to filter, tap to select)
- Input amount and target currency selection
- Smooth UI with basic animations
- Placeholder for logo (assets/logo.png) and app colors
- Ready-to-push to GitHub. Add pubspec.yaml and assets as noted below.

Required pubspec.yaml dependencies (add these):

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.6

Add an asset folder: assets/logo.png (put your trading-themed logo there)

How to build APK locally:
1. flutter build apk --release

Notes for GitHub/CI (high level):
- Add workflow file .github/workflows/flutter.yml that sets up Flutter, runs flutter pub get and flutter build apk
- Commit assets and pubspec.yaml

This is a simplified single-file example to jump-start your project. You can split widgets and services into separate files later.
*/

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(CryptoConverterApp());
}

class CryptoConverterApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickConvert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF0B1220),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _tabIndex = 0; // 0 = Crypto, 1 = Fiat

  // UI controllers
  TextEditingController _sourceController = TextEditingController();
  TextEditingController _searchController = TextEditingController();

  // Data
  List<Map<String, String>> _coins = []; // {"id":"bitcoin","symbol":"btc","name":"Bitcoin"}
  List<String> _fiats = ['usd','eur','uzs','rub','gbp','try','kzt'];

  String? _selectedSourceId; // coin id or fiat code
  String? _selectedTarget; // currency code
  double? _computedResult;
  bool _loading = false;

  // For debounce
  Timer? _debounce;
  List<Map<String, String>> _searchResults = [];

  // Animation
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: Duration(milliseconds: 450));
    _fetchCoinList();
    _selectedTarget = 'usd';
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _animController.dispose();
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(Duration(milliseconds: 200), () {
      _performLocalSearch(_searchController.text.trim());
    });
  }

  void _performLocalSearch(String q) {
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final Q = q.toUpperCase();
    final matches = _coins.where((c) {
      final symbol = (c['symbol'] ?? '').toUpperCase();
      final name = (c['name'] ?? '').toUpperCase();
      final id = (c['id'] ?? '').toUpperCase();
      return symbol.startsWith(Q) || name.contains(Q) || id.startsWith(Q);
    }).take(12).toList();
    setState(() {
      _searchResults = matches;
    });
  }

  Future<void> _fetchCoinList() async {
    try {
      final res = await http.get(Uri.parse('https://api.coingecko.com/api/v3/coins/list'));
      if (res.statusCode == 200) {
        final List parsed = json.decode(res.body);
        // We only keep id,symbol,name and limit size for performance in example
        final limited = parsed.map((e) => {
          'id': e['id'] ?? '',
          'symbol': e['symbol'] ?? '',
          'name': e['name'] ?? ''
        }).where((e) => (e['symbol']!.length > 0)).toList();
        setState(() {
          _coins = List<Map<String, String>>.from(limited);
        });
      }
    } catch (e) {
      print('coin list fetch failed: $e');
    }
  }

  Future<void> _calculate() async {
    final inputText = _sourceController.text.trim();
    if (inputText.isEmpty || _selectedTarget == null || _selectedSourceId == null) {
      _showSnack('Iltimos, barcha maydonlarni toʻldiring (amount, source va target).');
      return;
    }

    double amount = double.tryParse(inputText.replaceAll(',', '.')) ?? 0.0;
    if (amount <= 0) {
      _showSnack('Iltimos, toʻgʻri son kiriting.');
      return;
    }

    setState(() { _loading = true; _computedResult = null; });

    try {
      // Determine if source is crypto (we treat as coin id if exists in coins list), else fiat
      final isCrypto = _coins.any((c) => c['id'] == _selectedSourceId);

      // CoinGecko simple/price supports multiple vs_currencies, both fiat and certain crypto
      // We'll ask price of source in target (if source is crypto id, ask that id -> target)
      final sourceParam = isCrypto ? _selectedSourceId! : _selectedSourceId!; // for fiat, we will handle separately

      if (isCrypto) {
        // fetch price of crypto in target
        final url = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=$sourceParam&vs_currencies=${_selectedTarget!}');
        final resp = await http.get(url);
        if (resp.statusCode == 200) {
          final Map parsed = json.decode(resp.body);
          final rate = (parsed[sourceParam] ?? {})[_selectedTarget];
          if (rate == null) throw 'rate null';
          final result = amount * (rate as num).toDouble();
          setState(() { _computedResult = result; });
        } else throw 'status ${resp.statusCode}';
      } else {
        // source is fiat code (like usd). We'll convert source->target using simple/supported method:
        // approach: get price of BTC in both currencies and compute ratio BTC_price_target / BTC_price_source * amount
        final base = 'bitcoin';
        final url = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=$base&vs_currencies=${_selectedSourceId},${_selectedTarget}');
        final resp = await http.get(url);
        if (resp.statusCode == 200) {
          final Map parsed = json.decode(resp.body);
          final map = parsed[base];
          final srcRate = (map[_selectedSourceId] as num).toDouble();
          final tgtRate = (map[_selectedTarget] as num).toDouble();
          final result = amount * (tgtRate / srcRate);
          setState(() { _computedResult = result; });
        } else throw 'status ${resp.statusCode}';
      }
    } catch (e) {
      print('calc error: $e');
      _showSnack('Hisoblashda xatolik yuz berdi. Iltimos internetni tekshiring.');
    } finally {
      setState(() { _loading = false; });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Logo placeholder
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.indigoAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Icon(Icons.show_chart, size: 32)),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QuickConvert', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Oson va tez valyuta konvertori', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        )
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _tabButton('Crypto', 0),
        SizedBox(width: 8),
        _tabButton('Fiat', 1),
      ],
    );
  }

  Widget _tabButton(String title, int idx) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tabIndex = idx;
            _selectedSourceId = null;
            _searchController.clear();
            _searchResults = [];
            _computedResult = null;
          });
          _animController.forward(from: 0.0);
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 300),
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.indigoAccent.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_tabIndex == 0 ? 'Crypto yoki token kiriting' : 'Valyuta kodini kiriting (mas: usd, uzs)', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: _tabIndex == 0 ? 'masalan: BTC yoki bitcoin' : 'masalan: USD',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: Color(0xFF0E1624),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        SizedBox(height: 8),
        AnimatedSize(
          duration: Duration(milliseconds: 220),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (c,i){
                final item = _searchResults[i];
                return ListTile(
                  dense: true,
                  title: Text('${item['symbol']?.toUpperCase()} — ${item['name']}', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    setState(() {
                      _selectedSourceId = item['id'];
                      _searchController.text = '${item['symbol']?.toUpperCase()} — ${item['name']}';
                      _searchResults = [];
                    });
                  },
                );
              },
            ),
          ),
        )
      ],
    );
  }

  Widget _buildFiatPicker() {
    return Wrap(
      spacing: 8,
      children: _fiats.map((f) {
        final active = _selectedSourceId == f && _tabIndex==1;
        return ChoiceChip(
          label: Text(f.toUpperCase()),
          selected: active,
          onSelected: (v){
            setState((){
              _selectedSourceId = v ? f : null;
              _computedResult = null;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildAmountAndTarget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hisoblanishi kerak bo\'lgan qiymat', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 8),
        TextField(
          controller: _sourceController,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'Masalan: 7463',
            filled: true,
            fillColor: Color(0xFF0E1624),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        SizedBox(height: 12),
        Text('O\'tkazilishi kerak bo\'lgan valyuta (qidirib tanlang)', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            // open a bottom sheet to pick target from fiats list
            final picked = await showModalBottomSheet<String>(context: context, backgroundColor: Color(0xFF07101A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (_) {
              return Container(
                padding: EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _fiats.map((f){
                    return ListTile(
                      title: Text(f.toUpperCase()),
                      onTap: () => Navigator.of(context).pop(f),
                    );
                  }).toList(),
                ),
              );
            });
            if (picked != null) setState(() => _selectedTarget = picked);
          },
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(color: Color(0xFF0E1624), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text((_selectedTarget ?? 'tanlanmagan').toUpperCase()),
                Icon(Icons.keyboard_arrow_down)
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildResultCard() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: Color(0xFF08121A), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Natija', style: TextStyle(color: Colors.white70)),
          SizedBox(height: 8),
          if (_loading) Center(child: CircularProgressIndicator()) else if (_computedResult != null)
            Text('${_computedResult!.toStringAsFixed(6)} ${_selectedTarget?.toUpperCase() ?? ''}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
          else
            Text('Natija shu yerda chiqadi', style: TextStyle(color: Colors.white54)),
          SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _calculate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
              child: Text('Hisoblash', style: TextStyle(fontSize: 16)),
            ),
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              SizedBox(height: 18),
              _buildTabs(),
              SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: Duration(milliseconds: 300),
                        child: _tabIndex == 0 ? _buildCryptoTab() : _buildFiatTab(),
                      ),
                      SizedBox(height: 16),
                      _buildAmountAndTarget(),
                      SizedBox(height: 16),
                      _buildResultCard(),
                      SizedBox(height: 36),
                      Center(child: Text('Bizning maqsadimiz — odamlarga osonlik va yaxshilik', style: TextStyle(color: Colors.white54, fontSize: 12))),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCryptoTab() {
    return Column(
      key: ValueKey('crypto'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(),
        SizedBox(height: 12),
        if (_selectedSourceId != null) Text('Tanlangan: ${_selectedSourceId}', style: TextStyle(color: Colors.greenAccent))
      ],
    );
  }

  Widget _buildFiatTab() {
    return Column(
      key: ValueKey('fiat'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(),
        SizedBox(height: 12),
        _buildFiatPicker(),
        SizedBox(height: 8),
        if (_selectedSourceId != null) Text('Tanlangan fiat: ${_selectedSourceId?.toUpperCase()}', style: TextStyle(color: Colors.greenAccent))
      ],
    );
  }
}
