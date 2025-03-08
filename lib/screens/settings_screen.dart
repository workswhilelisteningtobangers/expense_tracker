import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:csv/csv.dart';
import 'dart:io'; // ✅ Required for Directory and File
import 'package:path_provider/path_provider.dart'; // ✅ Required for storage access
import 'package:permission_handler/permission_handler.dart'; // ✅ Required for requesting permissions
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatelessWidget {
  final Function(bool) toggleTheme;
  final bool isDarkMode;
  final Database database;
  final String selectedCurrency;
  final Function(String) changeCurrency;

  SettingsScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
    required this.database,
    required this.selectedCurrency,
    required this.changeCurrency,
  });

// ✅ AFTER: Now requests permission before accessing storage
// ✅ Request storage permissions properly before exporting
  Future<void> exportToCSV(BuildContext context) async {
    final List<Map<String, dynamic>> expenses = await database.query('expenses');

    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No expenses to export!')),
      );
      return;
    }

    List<List<String>> csvData = [
      ['ID', 'Date', 'Amount', 'Category', 'Description']
    ];
    for (var expense in expenses) {
      csvData.add([
        expense['id'].toString(),
        expense['date'],
        expense['amount'],
        expense['category'],
        expense['description'],
      ]);
    }

    String csvString = const ListToCsvConverter().convert(csvData);

    // ✅ Request permissions properly
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,  // Needed for Android 11+
    ].request();

    if (statuses[Permission.storage]!.isGranted || statuses[Permission.manageExternalStorage]!.isGranted) {
      // ✅ Get directory for saving the CSV file (Downloads folder)
      Directory directory = Directory('/storage/emulated/0/Download');
      String filePath = '${directory.path}/expenses_backup.csv';
      File file = File(filePath);

      await file.writeAsString(csvString);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expenses exported to: $filePath')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Storage permission is required to export CSV.")),
      );
    }
  }




  // 📥 IMPORT EXPENSES FROM CSV
  Future<void> importFromCSV(BuildContext context) async {
    try {
      // Open file picker for CSV files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        // User canceled the picker
        return;
      }

      String filePath = result.files.single.path!;
      File file = File(filePath);

      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected file does not exist!')),
        );
        return;
      }

      String csvString = await file.readAsString();
      List<List<dynamic>> csvData = const CsvToListConverter().convert(csvString);

      if (csvData.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid CSV file!')),
        );
        return;
      }

      // Insert CSV data into database
      await database.transaction((txn) async {
        for (int i = 1; i < csvData.length; i++) {
          await txn.insert('expenses', {
            'date': csvData[i][1],
            'amount': csvData[i][2].toString(),
            'category': csvData[i][3],
            'description': csvData[i][4],
          });
        }
      });

      Navigator.pop(context, true); // Refresh UI after import
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expenses imported successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing CSV: $e')),
      );
    }
  }

  // Function to reset expenses
  Future<void> resetExpenses(BuildContext context) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Reset Expenses"),
        content: Text("Are you sure you want to delete all expenses? This action cannot be undone."),
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
      await database.delete('expenses'); // Delete all expenses

      // Notify ExpenseHomePageState to update UI
      Navigator.pop(context, true); // Close settings screen and return true
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.dark_mode),
            title: Text('Dark Mode'),
            trailing: Switch(
              value: isDarkMode,
              onChanged: (value) {
                toggleTheme(value);
                Navigator.pop(context);
              },
            ),
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Reset Expenses'),
            subtitle: Text('This will delete all recorded expenses'),
            onTap: () => resetExpenses(context),
          ),
          ListTile(
            leading: Icon(Icons.attach_money),
            title: Text('Currency Format'),
            subtitle: Text('Selected: $selectedCurrency'),
            trailing: DropdownButton<String>(
              value: selectedCurrency,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  changeCurrency(newValue);
                  Navigator.pop(context, true); // Notify home screen that currency changed
                }
              },
              items: ["\$", "€", "£", "¥", "₹"].map((String currency) {
                return DropdownMenuItem<String>(
                  value: currency,
                  child: Text(currency),
                );
              }).toList(),
            ),
          ),
          ListTile(
            leading: Icon(Icons.file_upload),
            title: Text('Export Expenses (CSV)'),
            subtitle: Text('Save your expenses as a CSV file'),
            onTap: () => exportToCSV(context),
          ),
          ListTile(
            leading: Icon(Icons.file_download),
            title: Text('Import Expenses (CSV)'),
            subtitle: Text('Load expenses from a CSV file'),
            onTap: () => importFromCSV(context),
          ),
        ],
      ),
    );
  }
}
