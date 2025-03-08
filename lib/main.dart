import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'screens/settings_screen.dart';  // Import the settings screen
import 'package:shared_preferences/shared_preferences.dart';



void main() {
  runApp(ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  ExpenseTrackerAppState createState() => ExpenseTrackerAppState();
}

class ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  bool isDarkMode = false; // Default: Light mode
  String selectedCurrency = "\$"; // Default to USD

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 🔹 Load settings from storage
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool("isDarkMode") ?? false;
      selectedCurrency = prefs.getString("selectedCurrency") ?? "\$";
    });
  }

  // 🔹 Save currency selection
  Future<void> changeCurrency(String newCurrency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("selectedCurrency", newCurrency);

    setState(() {
      selectedCurrency = newCurrency;
    });
  }

  // 🔹 Save dark mode selection
  Future<void> toggleTheme(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isDarkMode", enabled);

    setState(() {
      isDarkMode = enabled;
    });
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: ExpenseHomePage(
        toggleTheme: toggleTheme,
        isDarkMode: isDarkMode,
        selectedCurrency: selectedCurrency, // Pass currency symbol
        changeCurrency: changeCurrency, // Pass function to change currency
      ),
    );
  }
}


class ExpenseHomePage extends StatefulWidget {
  final Function(bool) toggleTheme;
  final bool isDarkMode;
  final String selectedCurrency;
  final Function(String) changeCurrency; // Accept change function

  const ExpenseHomePage({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
    required this.selectedCurrency,
    required this.changeCurrency,
  });

  @override
  ExpenseHomePageState createState() => ExpenseHomePageState();
}


class ExpenseHomePageState extends State<ExpenseHomePage> {
  late Database database;
  List<Map<String, dynamic>> expenses = [];
  List<String> categories = [];
  String? selectedCategory;
  String currentYear = DateFormat('yyyy').format(DateTime.now());
  String currentMonth = DateFormat('MMMM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, 'expenses.db');

    database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE expenses (id INTEGER PRIMARY KEY, date TEXT, amount TEXT, category TEXT, description TEXT)');
        await db.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT UNIQUE)');
      },
    );
    await fetchCategories();
    await fetchExpenses();
  }

  Future<void> fetchCategories() async {
    final List<Map<String, dynamic>> data = await database.query('categories');
    setState(() {
      categories = data.map((e) => e['name'] as String).toList();
      if (categories.isEmpty) {
        categories.addAll(['Food', 'Gas', 'Utilities', 'Entertainment', 'Transport', 'Bills']);
        for (String category in categories) {
          database.insert('categories', {'name': category});
        }
      }
      selectedCategory = categories.isNotEmpty ? categories.first : null;
    });
  }

  Future<void> fetchExpenses() async {
    final List<Map<String, dynamic>> data = await database.query('expenses', orderBy: "date DESC");
    setState(() {
      expenses = data;
    });
  }

  Future<void> addExpense(String date, double amount, String category, String description) async {
    String formattedAmount = truncateToTwoDecimals(amount);
    await database.insert('expenses', {
      'date': date,
      'amount': formattedAmount,
      'category': category,
      'description': description,
    });
    await fetchExpenses();
  }

  Future<void> deleteCategory(String category) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Category"),
        content: Text("Are you sure you want to delete \"$category\"? "
            "This will remove the category and all associated expenses."),
        actions: [
          TextButton(
            child: Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text("Delete", style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      await database.delete('expenses', where: 'category = ?', whereArgs: [category]);
      await database.delete('categories', where: 'name = ?', whereArgs: [category]);

      // Fetch updated categories
      final List<Map<String, dynamic>> data = await database.query('categories');

      setState(() {
        categories = data.map((e) => e['name'] as String).toList();

        // ✅ If the deleted category was selected, clear selection
        if (selectedCategory == category) {
          selectedCategory = categories.isNotEmpty ? categories.first : null;
        }
      });

      // ✅ Force dropdown to refresh by rebuilding the entire dialog
      Navigator.pop(context);
      showAddExpenseDialog();
    }
  }


  void showEditExpenseDialog(Map<String, dynamic> expense) {
    final amountController = TextEditingController(text: expense['amount']);
    final descriptionController = TextEditingController(text: expense['description']);
    String selectedCategory = expense['category'];
    String selectedDate = expense['date'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Expense'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Amount'),
                  ),
                  Row(
                    children: [
                      Text("Date: $selectedDate"),
                      IconButton(
                        icon: Icon(Icons.calendar_today),
                        onPressed: () async {
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(selectedDate),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setDialogState(() {
                              selectedDate = pickedDate.toString().split(' ')[0];
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: 'Category'),
                    value: selectedCategory,
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        selectedCategory = newValue!;
                      });
                    },
                    items: categories.map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    )).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: Text('Save Changes'),
                  onPressed: () {
                    double amount = double.tryParse(amountController.text) ?? 0;
                    if (amount > 0) {
                      updateExpense(
                        expense['id'],
                        selectedDate,
                        amount,
                        selectedCategory,
                        descriptionController.text,
                      );
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> updateExpense(int id, String date, double amount, String category, String description) async {
    await database.update(
      'expenses',
      {
        'date': date,
        'amount': amount.toString(),
        'category': category,
        'description': description,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchExpenses(); // Refresh the list after updating
  }

  Future<void> deleteExpense(int id) async {
    await database.delete('expenses', where: 'id = ?', whereArgs: [id]);
    await fetchExpenses();
  }

  Future<void> addCategory(String newCategory) async {
    if (newCategory.isNotEmpty && !categories.contains(newCategory)) {
      await database.insert('categories', {'name': newCategory});
      await fetchCategories();
      setState(() {
        selectedCategory = newCategory;
      });
    }
  }

  String truncateToTwoDecimals(double value) {
    String stringValue = value.toStringAsFixed(10);
    List<String> parts = stringValue.split('.');
    if (parts.length == 2 && parts[1].length > 2) {
      return "${parts[0]}.${parts[1].substring(0, 2)}";
    }
    return value.toStringAsFixed(2);
  }

  void showAddExpenseDialog() {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController();
    String currentDate = DateTime.now().toString().split(' ')[0];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Add Expense'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Amount'),
                  ),
                  Row(
                    children: [
                      Text("Date: $currentDate"),
                      IconButton(
                        icon: Icon(Icons.calendar_today),
                        onPressed: () async {
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setDialogState(() {
                              currentDate = pickedDate.toString().split(' ')[0];
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Category Dropdown
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(labelText: 'Category'),
                          value: selectedCategory,
                          onChanged: (String? newValue) {
                            setDialogState(() {
                              selectedCategory = newValue;
                            });
                          },
                          items: categories.map((category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          )).toList(),
                        ),
                      ),

                      // Delete Button
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: selectedCategory != null ? () {
                          deleteCategory(selectedCategory!);
                        } : null, // Disable button if no category is selected
                      ),
                    ],
                  ),

                  TextButton(
                    child: Text("Add New Category"),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text("Add New Category"),
                            content: TextField(
                              controller: categoryController,
                              decoration: InputDecoration(labelText: 'Category Name'),
                            ),
                            actions: [
                              TextButton(
                                child: Text("Cancel"),
                                onPressed: () => Navigator.pop(context),
                              ),
                              ElevatedButton(
                                child: Text("Add"),
                                onPressed: () {
                                  String newCategory = categoryController.text.trim();
                                  if (newCategory.isNotEmpty && !categories.contains(newCategory)) {
                                    addCategory(newCategory);
                                    setDialogState(() {
                                      categories.add(newCategory);
                                      selectedCategory = newCategory;
                                    });
                                  }
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: Text('Add Expense'),
                  onPressed: () {
                    double amount = double.tryParse(amountController.text) ?? 0;
                    if (amount > 0 && selectedCategory != null) {
                      addExpense(currentDate, amount, selectedCategory!, descriptionController.text);
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>> expensesByYearMonthCategory = {};
    Map<String, double> yearTotals = {};
    Map<String, double> monthTotals = {};
    Map<String, double> categoryTotals = {};

    for (var expense in expenses) {
      DateTime date = DateTime.parse(expense['date']);
      String year = DateFormat('yyyy').format(date);
      String month = DateFormat('MMMM').format(date);
      String category = expense['category'];
      double amount = double.tryParse(expense['amount']) ?? 0;

      expensesByYearMonthCategory.putIfAbsent(year, () => {}).putIfAbsent(month, () => {}).putIfAbsent(category, () => []).add(expense);
      yearTotals[year] = (yearTotals[year] ?? 0) + amount;
      monthTotals["$year-$month"] = (monthTotals["$year-$month"] ?? 0) + amount;
      categoryTotals["$year-$month-$category"] = (categoryTotals["$year-$month-$category"] ?? 0) + amount;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Tracker'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    toggleTheme: widget.toggleTheme,
                    isDarkMode: widget.isDarkMode,
                    database: database,
                    selectedCurrency: widget.selectedCurrency, // Pass currency
                    changeCurrency: widget.changeCurrency, // Pass change function
                  ),
                ),
              ).then((value) {
                if (value == true) {
                  setState(() {
                    setState(() {});
                    fetchExpenses(); // Refresh the expense list when returning
                  });
                }
              });
            },
          ),
        ],
      ),
      body: ListView(
        children: expensesByYearMonthCategory.keys.map((year) {
          return ExpansionTile(
            title: Text("$year (${widget.selectedCurrency}${yearTotals[year]!.toStringAsFixed(2)})"),
            initiallyExpanded: year == currentYear, // Expands only for the current year
            children: expensesByYearMonthCategory[year]!.keys.map((month) {
              return ExpansionTile(
                title: Text("$month (${widget.selectedCurrency}${monthTotals["$year-$month"]!.toStringAsFixed(2)})"),
                initiallyExpanded: year == currentYear && month == currentMonth, // Expands only for the current month
                children: expensesByYearMonthCategory[year]![month]!.keys.map((category) {
                  return ExpansionTile(
                    title: Text("$category (${widget.selectedCurrency}${categoryTotals["$year-$month-$category"]!.toStringAsFixed(2)})"),
                    children: expensesByYearMonthCategory[year]![month]![category]!.map((expense) {
                      return ListTile(
                        title: Text("${widget.selectedCurrency}${expense['amount']} - ${expense['description']}"),
                        subtitle: Text(expense['date']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min, // Ensures the buttons don't take up full width
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => showEditExpenseDialog(expense),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteExpense(expense['id']),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              );
            }).toList(),
          );
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddExpenseDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
