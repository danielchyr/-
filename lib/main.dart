import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RollingBudgetApp());
}

class RollingBudgetApp extends StatelessWidget {
  const RollingBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '每週飲食滾動預算',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
      ),
      home: const BudgetHomePage(),
    );
  }
}

// 單日花費資料模型
class DayExpense {
  final String dayName;
  bool isRecorded;
  int directTotal;
  bool useBreakdown;
  int breakfast;
  int lunch;
  int dinner;
  int drink;
  int grocery;

  DayExpense({
    required this.dayName,
    this.isRecorded = false,
    this.directTotal = 0,
    this.useBreakdown = false,
    this.breakfast = 0,
    this.lunch = 0,
    this.dinner = 0,
    this.drink = 0,
    this.grocery = 0,
  });

  int get total => useBreakdown
      ? (breakfast + lunch + dinner + drink + grocery)
      : directTotal;

  Map<String, dynamic> toJson() => {
        'dayName': dayName,
        'isRecorded': isRecorded,
        'directTotal': directTotal,
        'useBreakdown': useBreakdown,
        'breakfast': breakfast,
        'lunch': lunch,
        'dinner': dinner,
        'drink': drink,
        'grocery': grocery,
      };

  factory DayExpense.fromJson(Map<String, dynamic> json) => DayExpense(
        dayName: json['dayName'] ?? '',
        isRecorded: json['isRecorded'] ?? false,
        directTotal: json['directTotal'] ?? 0,
        useBreakdown: json['useBreakdown'] ?? false,
        breakfast: json['breakfast'] ?? 0,
        lunch: json['lunch'] ?? 0,
        dinner: json['dinner'] ?? 0,
        drink: json['drink'] ?? 0,
        grocery: json['grocery'] ?? 0,
      );
}

// 歷史紀錄資料模型
class WeekRecord {
  final String dateRange;
  final int budget;
  final int spent;

  WeekRecord({
    required this.dateRange,
    required this.budget,
    required this.spent,
  });

  int get balance => budget - spent;

  Map<String, dynamic> toJson() => {
        'dateRange': dateRange,
        'budget': budget,
        'spent': spent,
      };

  factory WeekRecord.fromJson(Map<String, dynamic> json) => WeekRecord(
        dateRange: json['dateRange'] ?? '',
        budget: json['budget'] ?? 2250,
        spent: json['spent'] ?? 0,
      );
}

class BudgetHomePage extends StatefulWidget {
  const BudgetHomePage({super.key});

  @override
  State<BudgetHomePage> createState() => _BudgetHomePageState();
}

class _BudgetHomePageState extends State<BudgetHomePage> {
  static const List<String> _weekDays = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日'
  ];

  int _weeklyBudget = 2250;
  List<DayExpense> _days = [];
  List<WeekRecord> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDefaultDays();
    _loadData();
  }

  void _initDefaultDays() {
    _days = _weekDays.map((name) => DayExpense(dayName: name)).toList();
  }

  // 讀取手機本地資料
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weeklyBudget = prefs.getInt('weekly_budget') ?? 2250;
      final daysString = prefs.getString('days_data');
      if (daysString != null) {
        final List decoded = jsonDecode(daysString);
        _days = decoded.map((e) => DayExpense.fromJson(e)).toList();
      }
      final historyString = prefs.getString('history_data');
      if (historyString != null) {
        final List decoded = jsonDecode(historyString);
        _history = decoded.map((e) => WeekRecord.fromJson(e)).toList();
      }
      _isLoading = false;
    });
  }

  // 儲存資料至手機本地
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weekly_budget', _weeklyBudget);
    await prefs.setString(
        'days_data', jsonEncode(_days.map((e) => e.toJson()).toList()));
    await prefs.setString(
        'history_data', jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  // 計算目前已記錄的總開銷
  int get _totalSpent =>
      _days.where((d) => d.isRecorded).fold(0, (sum, d) => sum + d.total);

  // 總剩餘預算
  int get _remainingBudget => _weeklyBudget - _totalSpent;

  // 找到最後一個已記錄的日子索引 (-1 代表整週尚未開始記錄)
  int get _lastRecordedIndex => _days.lastIndexWhere((d) => d.isRecorded);

  // 剩餘未過天數 (依最後一筆紀錄往後推算，若都沒記則為 7 天)
  int get _remainingDaysAfterLast {
    if (_lastRecordedIndex == -1) return 7;
    return 6 - _lastRecordedIndex;
  }

  // 接下來平均每天可用額度 (無條件捨去取整數，若透支則顯示 0)
  int get _rollingDailyAllowance {
    final remDays = _remainingDaysAfterLast;
    if (remDays <= 0) return 0;
    if (_remainingBudget <= 0) return 0;
    return (_remainingBudget / remDays).floor();
  }

  // 計算截至特定某一天（含當日）的累計花費
  int _cumulativeSpentUpTo(int index) {
    int sum = 0;
    for (int i = 0; i <= index; i++) {
      if (_days[i].isRecorded) {
        sum += _days[i].total;
      }
    }
    return sum;
  }

  // 修改每週總預算彈窗
  void _showEditBudgetDialog() {
    final controller = TextEditingController(text: _weeklyBudget.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定每週飲食總預算'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            prefixText: 'NT\$ ',
            border: OutlineInputBorder(),
            labelText: '每週總預算',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0) {
                setState(() => _weeklyBudget = val);
                _saveData();
              }
              Navigator.pop(context);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  // 單日花費輸入底部面板
  void _showDayEditor(int index) {
    final day = _days[index];
    bool useBreakdown = day.useBreakdown;

    final directCtrl = TextEditingController(
        text: day.isRecorded && !day.useBreakdown && day.directTotal > 0
            ? day.directTotal.toString()
            : '');
    final bCtrl = TextEditingController(
        text: day.breakfast > 0 ? day.breakfast.toString() : '');
    final lCtrl =
        TextEditingController(text: day.lunch > 0 ? day.lunch.toString() : '');
    final dCtrl = TextEditingController(
        text: day.dinner > 0 ? day.dinner.toString() : '');
    final drCtrl =
        TextEditingController(text: day.drink > 0 ? day.drink.toString() : '');
    final gCtrl = TextEditingController(
        text: day.grocery > 0 ? day.grocery.toString() : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '記錄 ${day.dayName} 花費',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('單筆總額')),
                            ButtonSegment(value: true, label: Text('分項加總')),
                          ],
                          selected: {useBreakdown},
                          onSelectionChanged: (val) {
                            setModalState(() => useBreakdown = val.first);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!useBreakdown)
                      TextField(
                        controller: directCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: '當日飲食總花費 (可填 0 代表今日零花費)',
                          prefixText: 'NT\$ ',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: _buildCategoryField('早餐', bCtrl)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _buildCategoryField('午餐', lCtrl)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildCategoryField('晚餐', dCtrl)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _buildCategoryField('飲品 / 咖啡', drCtrl)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildCategoryField('自炊食材採買', gCtrl),
                        ],
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (day.isRecorded)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                day.isRecorded = false;
                                day.directTotal = 0;
                                day.breakfast = 0;
                                day.lunch = 0;
                                day.dinner = 0;
                                day.drink = 0;
                                day.grocery = 0;
                              });
                              _saveData();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            label: const Text('清除當日紀錄',
                                style: TextStyle(color: Colors.red)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              day.useBreakdown = useBreakdown;
                              if (useBreakdown) {
                                day.breakfast = int.tryParse(bCtrl.text) ?? 0;
                                day.lunch = int.tryParse(lCtrl.text) ?? 0;
                                day.dinner = int.tryParse(dCtrl.text) ?? 0;
                                day.drink = int.tryParse(drCtrl.text) ?? 0;
                                day.grocery = int.tryParse(gCtrl.text) ?? 0;
                              } else {
                                day.directTotal =
                                    int.tryParse(directCtrl.text) ?? 0;
                              }
                              day.isRecorded = true;
                            });
                            _saveData();
                            Navigator.pop(context);
                          },
                          child: const Text('儲存紀錄'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'NT\$ ',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  // 結算並開啟新一週確認彈窗
  void _confirmSettleWeek() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('結算並開啟新一週'),
        content: Text(
          '本週總預算：NT\$ $_weeklyBudget\n'
          '本週已花費：NT\$ $_totalSpent\n'
          '本週結餘：NT\$ $_remainingBudget\n\n'
          '確定要將本週存入歷史紀錄，並清空週一至週日的花費嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final now = DateTime.now();
              final dateStr =
                  '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} 結算';
              setState(() {
                _history.insert(
                  0,
                  WeekRecord(
                    dateRange: dateStr,
                    budget: _weeklyBudget,
                    spent: _totalSpent,
                  ),
                );
                _initDefaultDays();
              });
              _saveData();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已完成本週結算，開啟新一週預算！')),
              );
            },
            child: const Text('確認結算'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool isOverBudget = _remainingBudget < 0;
    final double progress =
        (_totalSpent / (_weeklyBudget > 0 ? _weeklyBudget : 1)).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('每週飲食滾動預算',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '調整每週總預算',
            onPressed: _showEditBudgetDialog,
            icon: const Icon(Icons.tune),
          ),
          TextButton.icon(
            onPressed: _confirmSettleWeek,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('結算新一週'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 頂部動態滾動看板
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isOverBudget
                    ? [const Color(0xFFB71C1C), const Color(0xFFD32F2F)]
                    : [const Color(0xFF1B5E20), const Color(0xFF388E3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _remainingDaysAfterLast > 0
                          ? '接下來 $_remainingDaysAfterLast 天・平均每天可花'
                          : '本週最後一天已記錄完畢',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    InkWell(
                      onTap: _showEditBudgetDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '週預算 NT\$ $_weeklyBudget ✎',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _remainingDaysAfterLast > 0
                          ? 'NT\$ $_rollingDailyAllowance'
                          : 'NT\$ $_remainingBudget',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _remainingDaysAfterLast > 0 ? '/ 天' : '(本週總結餘)',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOverBudget ? Colors.amberAccent : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '累計已花：NT\$ $_totalSpent',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    Text(
                      isOverBudget
                          ? '已超支：NT\$ ${_remainingBudget.abs()}'
                          : '剩餘總額：NT\$ $_remainingBudget',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            '每日花費與動態滾動試算（點擊卡片記錄）',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          // 週一至週日清單
          ...List.generate(_days.length, (index) {
            final day = _days[index];
            final int cumSpent = _cumulativeSpentUpTo(index);
            final int remAfterToday = _weeklyBudget - cumSpent;
            final int daysLeftAfterToday = 6 - index;
            final int nextAvg = (daysLeftAfterToday > 0 && remAfterToday > 0)
                ? (remAfterToday / daysLeftAfterToday).floor()
                : 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: day.isRecorded
                      ? const Color(0xFF2E7D32).withOpacity(0.4)
                      : Colors.grey.shade200,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showDayEditor(index),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: day.isRecorded
                            ? const Color(0xFFE8F5E9)
                            : Colors.grey.shade100,
                        child: Text(
                          day.dayName.substring(2),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: day.isRecorded
                                ? const Color(0xFF2E7D32)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              day.dayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (day.isRecorded)
                              Text(
                                daysLeftAfterToday > 0
                                    ? '當日結束剩 \$$remAfterToday ｜ 接下來 $daysLeftAfterToday 天日均 \$$nextAvg'
                                    : '本週結算剩餘：\$$remAfterToday',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: remAfterToday >= 0
                                      ? const Color(0xFF2E7D32)
                                      : Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            else
                              Text(
                                '點擊輸入當日飲食花費',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        day.isRecorded ? 'NT\$ ${day.total}' : '+ 記錄',
                        style: TextStyle(
                          fontSize: day.isRecorded ? 17 : 14,
                          fontWeight: FontWeight.bold,
                          color: day.isRecorded
                              ? Colors.black87
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // 歷史週期結算紀錄
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '歷史週期結算紀錄',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _history.clear());
                    _saveData();
                  },
                  child: const Text('清空紀錄',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
            ..._history.map((rec) => Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(rec.dateRange,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle:
                        Text('預算 \$${rec.budget} ｜ 總花費 \$${rec.spent}'),
                    trailing: Text(
                      rec.balance >= 0
                          ? '結餘 +\$${rec.balance}'
                          : '超支 -\$${rec.balance.abs()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rec.balance >= 0
                            ? const Color(0xFF2E7D32)
                            : Colors.red,
                      ),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
