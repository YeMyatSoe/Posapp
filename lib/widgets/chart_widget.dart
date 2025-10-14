import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ChartWidget extends StatelessWidget {
  const ChartWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                return Text('Day ${value.toInt() + 1}');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 5),
              FlSpot(1, 3),
              FlSpot(2, 4),
              FlSpot(3, 7),
              FlSpot(4, 6),
              FlSpot(5, 8),
              FlSpot(6, 5),
            ],
            isCurved: true,
            barWidth: 3,
            color: Colors.blueAccent,
            dotData: FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
