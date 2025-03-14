import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Labeli
  String vati = "Loading...";
  String cena = "Loading...";

  // Povezava za graf
  late PostgreSQLConnection connection;

  @override
  void initState() {
    super.initState();
    // Povežemo se na bazo (za graf)
    connectToDatabase();
    // Ob zagonu aplikacije dobimo vrednost za "vati" iz HTTP requesta
    fetchVati();
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
      print("Baza povezana");

      // Ko se povežemo, takoj pridobimo še 'Cena' iz baze
      await fetchCena();
    } catch (e) {
      print("Database connection error: $e");
    }
  }

  // HTTP GET za "vati"
  Future<void> fetchVati() async {
    try {
      final response =
          await http.get(Uri.parse("http://192.168.0.166:3000/run-live"));
      if (response.statusCode == 200) {
        setState(() {
          vati = response.body.trim();
        });
      } else {
        print("HTTP request error: ${response.statusCode}");
      }
    } catch (e) {
      print("Napaka pri HTTP requestu: $e");
    }
  }

  // Branje vrednosti "Cena" iz baze
  Future<void> fetchCena() async {
    if (connection.isClosed) {
      print("Povezava ni odprta, fetchCena ne bo izveden.");
      return;
    }
    try {
      // Tukaj prilagodi SQL poizvedbo, če se stolpec imenuje drugače
      List<List<dynamic>> result = await connection.query(
        """
        SELECT dnevi_izracun
        FROM informacije
        ORDER BY datum DESC, ura DESC
        LIMIT 1;
        """
      );
      if (result.isNotEmpty) {
        setState(() {
          cena = result.first.first.toString();
        });
      }
    } catch (e) {
      print("Napaka pri pridobivanju cene: $e");
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
      title: 'Graf dnevne porabe',
      home: Scaffold(
        appBar: AppBar(title: const Text("Database & HTTP Test")),
        body: Column(
          children: [
            // Label "Vati"
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Vati: $vati",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
            ),
            // Label "Cena"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                "Cena: $cena",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: DailyConsumptionChart(connection: connection),
            ),
            // Gumb za ročno osveževanje "Vati" (lahko po potrebi dodaš še fetchCena, če želiš)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: () {
                  fetchVati();   // Osveži Vati
                  fetchCena();  // Če želiš ob istem kliku osvežiti tudi ceno, razkomentiraj
                },
                child: const Text("Osveži"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DataPoint {
  final double time;
  final double poraba;
  DataPoint({required this.time, required this.poraba});
}

class DailyConsumptionChart extends StatefulWidget {
  final PostgreSQLConnection connection;
  const DailyConsumptionChart({Key? key, required this.connection}) : super(key: key);

  @override
  State<DailyConsumptionChart> createState() => _DailyConsumptionChartState();
}

class _DailyConsumptionChartState extends State<DailyConsumptionChart> {
  List<DataPoint> dataPoints = [];
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    fetchData();
    // Osvežujemo graf vsako minuto
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      fetchData();
    });
  }

  Future<void> fetchData() async {
    if (widget.connection.isClosed) {
      print("Povezava ni odprta, fetchData ne bo izveden.");
      return;
    }
    try {
      print("Izvajam poizvedbo za podatke...");
      List<List<dynamic>> results = await widget.connection.query(
        """
        SELECT poraba, (ura)::text AS ura_str
        FROM informacije
        WHERE datum = CURRENT_DATE
        ORDER BY ura
        """
      );
      print("Rezultati iz baze: $results");
      List<DataPoint> tempPoints = [];
      for (var row in results) {
        double poraba = row[0] is int
            ? (row[0] as int).toDouble()
            : (row[0] as double);
        String timeString = row[1].toString();
        List<String> parts = timeString.split(':');
        int hours = int.parse(parts[0]);
        int minutes = int.parse(parts[1]);
        double seconds = double.parse(parts[2]);
        double totalMinutes = hours * 60 + minutes + (seconds / 60);
        tempPoints.add(DataPoint(time: totalMinutes, poraba: poraba));
      }
      setState(() {
        dataPoints = tempPoints;
      });
    } catch (e) {
      print("Napaka pri pridobivanju podatkov: $e");
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    List<FlSpot> spots = List.generate(
      dataPoints.length,
      (index) => FlSpot(index.toDouble(), dataPoints[index].poraba),
    );

    double minX = 0;
    double maxX = dataPoints.length - 1.toDouble();
    double maxDataValue = dataPoints.map((dp) => dp.poraba).reduce(max);
    double calculatedMaxY = max(maxDataValue, 0.0001) * 1.1;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: calculatedMaxY,
          minX: minX,
          maxX: maxX,
          gridData: FlGridData(show: true),
          lineTouchData: LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: const Text("Čas"),
              axisNameSize: 20,
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int index = value.round();
                  if (index >= 0 && index < dataPoints.length) {
                    int absMinutes = dataPoints[index].time.round();
                    int hrs = absMinutes ~/ 60;
                    int mins = absMinutes % 60;
                    return Text(
                      "${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}",
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text("Poraba"),
              axisNameSize: 20,
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.001,
                getTitlesWidget: (value, meta) {
                  if (value < 0) {
                    return const SizedBox();
                  }
                  return Text(
                    value.toStringAsFixed(4),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}
