import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String connectionStatus = "Connecting...";
  late PostgreSQLConnection connection;

  @override
  void initState() {
    super.initState();
    connectToDatabase();
  }

  Future<void> connectToDatabase() async {
    connection = PostgreSQLConnection(
      "ep-wandering-dew-a8d03se0-pooler.eastus2.azure.neon.tech",
      5432,
      "neondb",
      username: "neondb_owner",
      password: "npg_kMfQCWl59RIV",
      useSSL: true,
    );

    try {
      await connection.open();
      setState(() {
        connectionStatus = "Connected ✅";
      });
    } catch (e) {
      setState(() {
        connectionStatus = "Failed to connect ❌";
      });
      print("Database connection error: $e");
    }
  }

  @override
  void dispose() {
    connection.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("Database Connection Test")),
        body: Center(
          child: Text(
            connectionStatus,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
