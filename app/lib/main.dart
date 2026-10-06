import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

// InfluxDB 접속 정보는 코드에 넣지 않고 실행 시 주입합니다.
// flutter run --dart-define=INFLUX_URL=http://<서버IP>:8086 --dart-define=INFLUX_TOKEN=<토큰>
const influxUrl = String.fromEnvironment('INFLUX_URL', defaultValue: 'http://localhost:8086');
const influxToken = String.fromEnvironment('INFLUX_TOKEN');
const influxOrg = String.fromEnvironment('INFLUX_ORG', defaultValue: 'csu');
const influxBucket = String.fromEnvironment('INFLUX_BUCKET', defaultValue: 'IoT');

void main() {
  runApp(MaterialApp(home: InfluxGraphPage()));
}

class InfluxGraphPage extends StatefulWidget {
  @override
  _InfluxGraphPageState createState() => _InfluxGraphPageState();
}

class _InfluxGraphPageState extends State<InfluxGraphPage> {
  Map<String, List<FlSpot>> chartData = {
    'value1': [],
    'value2': [],
    'value3': [],
  };
  bool loading = true;
  double? startTimestamp;

  Timer? _timer;

  final measurements = ['value1', 'value2', 'value3'];

  // 그래프별 선 색상 지정
  final Map<String, String> measurementNames = {
    'value1': 'Temperature (°C)',
    'value2': 'Humidity (%)',
    'value3': 'Pressure (hPa)',
  };
  final Map<String, Color> lineColors = {
    'value1': Colors.red,
    'value2': Colors.blue,
    'value3': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    loadData();

    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      fetchNewData();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> loadData() async {
    // 로딩 상태는 함수 시작 시 바로 설정됩니다.
    // (finally에서 setState가 호출되므로 여기서 호출할 필요 없음)
    loading = true;

    try {
      final rangeStart = DateTime.now().toUtc().subtract(Duration(minutes: 5));
      for (final m in measurements) {
        final data = await fetchInfluxData(
          measurement: m,
          rangeStart: rangeStart,
        );
        if (data.length > 1000) {
          chartData[m] = data.sublist(data.length - 1000);
        } else {
          chartData[m] = data;
        }
      }

      if (chartData['value1']!.isNotEmpty) {
        startTimestamp = chartData['value1']!.last.x;
      }
    } catch (e) {
      // [오류 처리] 오류가 발생하면 개발자에게 로그를 보여주고,
      // 사용자에게는 화면 하단에 스낵바 메시지를 띄웁니다.
      print('데이터 로드 중 에러 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('데이터를 불러오지 못했습니다: $e')));
      }
    } finally {
      // [항상 실행] 성공하든 실패하든, 마지막에는 로딩 상태를 false로 변경합니다.
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> fetchNewData() async {
    if (startTimestamp == null) return;

    try {
      final sinceDateTime = DateTime.fromMillisecondsSinceEpoch(
        startTimestamp!.toInt(),
      );

      bool dataWasUpdated = false; // [성능 최적화] 데이터 업데이트 여부 추적
      for (final m in measurements) {
        final newData = await fetchInfluxData(
          measurement: m,
          since: sinceDateTime,
        );
        final filtered =
            newData.where((d) => d.x > (chartData[m]?.last.x ?? 0)).toList();
        if (filtered.isNotEmpty) {
          dataWasUpdated = true; // 새 데이터가 있으면 플래그를 true로 변경
          chartData[m]?.addAll(filtered);
          if (chartData[m]!.length > 1000) {
            chartData[m] = chartData[m]!.sublist(chartData[m]!.length - 1000);
          }
        }
      }

      // [성능 최적화] 새 데이터가 실제로 있을 때만 화면을 갱신합니다.
      if (dataWasUpdated && mounted) {
        setState(() {
          if (chartData['value1']!.isNotEmpty) {
            startTimestamp = chartData['value1']!.last.x;
          }
        });
      }
    } catch (e) {
      // [오류 처리] 백그라운드 업데이트 오류는 사용자에게 알리지 않고,
      // 개발자를 위해 로그만 남깁니다. (다음 주기에 다시 시도)
      print('새 데이터 가져오기 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(223, 255, 255, 255),
      appBar: AppBar(
        title: Text('ChangsinM', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),

      body:
          loading
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: measurements.length,
                itemBuilder: (context, index) {
                  final measurement = measurements[index];
                  final dataPoints = chartData[measurement] ?? [];
                  final color = lineColors[measurement] ?? Colors.blue;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          measurementNames[measurement] ??
                              measurement.toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 20),
                        Container(
                          height: 200,
                          child: SimpleLineChart(
                            dataPoints: dataPoints,
                            lineColor: color,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}

Future<List<FlSpot>> fetchInfluxData({
  required String measurement,
  DateTime? since,
  DateTime? rangeStart,
}) async {
  final startTime =
      since?.toUtc() ??
      rangeStart?.toUtc() ??
      DateTime.now().toUtc().subtract(Duration(minutes: 10));

  final rangeFilter = '  |> range(start: ${startTime.toIso8601String()})';

  final fluxQuery = '''
from(bucket: "$influxBucket")
$rangeFilter
  |> filter(fn: (r) => r["_measurement"] == "$measurement")
  |> aggregateWindow(every: 30s, fn: mean, createEmpty: true)
  |> yield(name: "mean")
''';

  final response = await http.post(
    Uri.parse('$influxUrl/api/v2/query?org=$influxOrg'),
    headers: {
      'Authorization': 'Token $influxToken',
      'Content-Type': 'application/vnd.flux',
      'Accept': 'application/csv',
    },
    body: fluxQuery,
  );

  if (response.statusCode != 200) {
    throw Exception(
      'Failed to fetch $measurement data: ${response.statusCode}',
    );
  }

  final lines = const LineSplitter().convert(response.body);
  int timeIndex = -1;
  int valueIndex = -1;
  final List<FlSpot> dataPoints = [];

  for (var line in lines) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;

    final parts = line.split(',');

    if (timeIndex == -1 || valueIndex == -1) {
      if (parts.contains('_time') && parts.contains('_value')) {
        timeIndex = parts.indexOf('_time');
        valueIndex = parts.indexOf('_value');
        continue;
      }
    }

    try {
      final timeStr = parts[timeIndex];
      final valueStr = parts[valueIndex];
      if (valueStr.trim().isEmpty) continue;

      final timestamp =
          DateTime.parse(timeStr).millisecondsSinceEpoch.toDouble();
      final value = double.parse(valueStr);

      dataPoints.add(FlSpot(timestamp, value));
    } catch (e) {
      continue;
    }
  }

  return dataPoints;
}

class SimpleLineChart extends StatelessWidget {
  final List<FlSpot> dataPoints;
  final Color lineColor;

  SimpleLineChart({required this.dataPoints, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return Center(child: Text("데이터 없음"));
    }

    // Y축 최소값, 최대값 계산
    final minY = dataPoints.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    final maxY = dataPoints.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    // Y축 간격 (5구간)
    final interval = ((maxY - minY) / 5).ceilToDouble();

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints,
            isCurved: false,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: lineColor, // 도트 안쪽 색상
                  strokeWidth: 4, // 테두리 두께
                  strokeColor: Colors.white, // 흰색 테두리 설정
                );
              },
            ),
            barWidth: 5,
            color: lineColor,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withOpacity(0.4),
                  const Color.fromRGBO(255, 255, 255, 1),
                ],
                stops: [0.0, 0.8],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval == 0 ? 1 : interval, // interval이 0이면 1로 설정
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(fontSize: 10),
                  ),
                );
              },
              reservedSize: 40,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 60 * 1000,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                final formatted =
                    "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}";
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(formatted, style: TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        minX: dataPoints.first.x,
        maxX: dataPoints.last.x,
        minY: minY,
        maxY: maxY,
      ),
    );
  }
}
