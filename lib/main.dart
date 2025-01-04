import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  // 配置窗口
  WindowOptions windowOptions = WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 移除调试标记
      home: SerialPortExample(),
    );
  }
}

class SerialPortExample extends StatefulWidget {
  @override
  _SerialPortExampleState createState() => _SerialPortExampleState();
}

class _SerialPortExampleState extends State<SerialPortExample> {
  List<String> availablePorts = [];
  String? selectedPort;
  SerialPort? port;
  SerialPortReader? reader;
  String weightDisplay = '';
  Timer? _timer;
  final TextEditingController _sendController = TextEditingController();
  String _buffer = '';
  String _currentUnit = 'G'; // 添加单位跟踪变量
  FlutterTts flutterTts = FlutterTts();
  double? _lastSpokenWeight;
  DateTime? _lastSpeakTime;
  Timer? _speakTimer;
  double? _pendingWeight;

  @override
  void initState() {
    super.initState();
    _getAvailablePorts();
    _initTts();
  }

  // 初始化TTS引擎
  Future<void> _initTts() async {
    await flutterTts.setLanguage("zh-CN"); // 设置中文语音
    await flutterTts.setSpeechRate(0.5); // 设置语速(0.1-2.0)
    await flutterTts.setVolume(1.0); // 设置音量(0.0-1.0)
    await flutterTts.setPitch(1.0); // 设置音调(0.5-2.0)
  }

  // 播报重量的方法
  Future<void> _speakWeight(double weight) async {
    // 检查是否需要播报
    if (!_shouldSpeak(weight)) {
      return;
    }

    // 根据不同单位构建播报文本
    String text;
    switch (_currentUnit) {
      case 'CT':
        text = "${weight.toStringAsFixed(3)}克拉";
        break;
      case 'TL':
        text = "${weight.toStringAsFixed(3)}钱";
        break;
      case 'MO':
        text = "${weight.toStringAsFixed(3)}毫米";
        break;
      case 'OT':
        text = "${weight.toStringAsFixed(3)}盎司";
        break;
      default:
        text = "${weight.toStringAsFixed(3)}克";
    }

    // 执行语音播报
    await flutterTts.speak(text);

    // 更新最后播报的记录
    _lastSpokenWeight = weight;
    _lastSpeakTime = DateTime.now();
  }

  // 判断是否需要播报重量
  bool _shouldSpeak(double currentWeight) {
    // 首次播报
    if (_lastSpokenWeight == null || _lastSpeakTime == null) {
      return true;
    }

    // 计算重量变化
    double weightDiff = (currentWeight - _lastSpokenWeight!).abs();

    // 计算时间间隔（秒）
    int timeDiff = DateTime.now().difference(_lastSpeakTime!).inSeconds;

    // 满足以下任一条件时播报：
    // 1. 重量变化超过0.5
    // 2. 距离上次播报超过2秒
    return weightDiff >= 0.5 || timeDiff >= 2;
  }

  void _updateWeight(double newWeight) {
    setState(() {
      weightDisplay = newWeight.toStringAsFixed(1) + '克';
      _speakWeight(newWeight);
    });
  }

  void _getAvailablePorts() {
    setState(() {
      availablePorts = SerialPort.availablePorts;
      if (availablePorts.isNotEmpty) {
        selectedPort = availablePorts.first;
      }
    });
    print('Available ports: $availablePorts');
  }

  void _startWeightTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      _sendCommand('O8');
    });
  }

  void _stopWeightTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _connectToPort() {
    if (selectedPort == null) {
      _showMessage('请选择一个串口设备');
      return;
    }

    try {
      port = SerialPort(selectedPort!);

      if (!port!.openReadWrite()) {
        _showMessage('无法打开串口');
        return;
      }

      final config = SerialPortConfig();
      config.baudRate = 1200;
      config.stopBits = 1;
      config.bits = 8;
      port!.config = config;
      print('串口已打开并配置波特率为 1200, 停止位为 1, 数据位为 8');

      reader = SerialPortReader(port!, timeout: 0);
      reader!.stream.listen(
        (data) {
          final response = String.fromCharCodes(data);
          _buffer += response;

          // 处理命令响应
          if (_buffer.contains('A00')) {
            _buffer = _buffer.replaceAll('A00', '');
          }

          // 处理重量数据
          if (_buffer.contains('G S') ||
              _buffer.contains('CT S') ||
              _buffer.contains('TL S') ||
              _buffer.contains('MO') ||
              _buffer.contains('OT S')) {
            // 更新单位
            if (_buffer.contains('CT S')) {
              _currentUnit = 'CT';
            } else if (_buffer.contains('TL S')) {
              _currentUnit = 'TL';
            } else if (_buffer.contains('MO')) {
              _currentUnit = 'MO';
            } else if (_buffer.contains('OT S')) {
              _currentUnit = 'OT';
            } else {
              _currentUnit = 'G';
            }

            _processWeightData(_buffer);
            _buffer = ''; // 清空缓冲区
          }
        },
        onError: (error) {
          print('串口读取错误: $error');
          _showMessage('数据读取错误');
        },
      );

      _startWeightTimer();
      _showMessage('串口已连接');
    } catch (e) {
      print('连接错误: $e');
      _showMessage('连接失败: ${e.toString()}');
      port?.close();
      port = null;
    }
  }

  void _disconnectPort() {
    _stopWeightTimer();
    reader?.close();
    port?.close();
    port = null;
    _buffer = '';
    setState(() {
      weightDisplay = '';
    });
    _showMessage('串口已断开');
  }

  void _sendCommand(String command) {
    if (port == null || !port!.isOpen) {
      _showMessage('串口未打开，无法发送命令');
      return;
    }

    String formattedCommand;
    switch (command) {
      case 'T':
        formattedCommand = 'T(SP)54H20H\r\n';
        break;
      case 'UNIT':
        // 发送单位切换命令
        formattedCommand = 'U\r\n';
        break;
      default:
        formattedCommand = command + '\r\n';
        break;
    }

    final bytes = formattedCommand.codeUnits;
    port!.write(Uint8List.fromList(bytes));
    print('发送命令: $formattedCommand');
  }

  void _handleWeightResponse(String response) {
    setState(() {
      weightDisplay = response.trim();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // 处理重量数据
  void _processWeightData(String data) {
    try {
      // 匹配重量数值（带正号的数字）
      final pattern = RegExp(r'[+]\d+\.\d+');
      final match = pattern.firstMatch(data);
      if (match != null) {
        String numberStr = match.group(0)!;
        double weight = double.parse(numberStr);

        setState(() {
          // 更新显示，保持3位小数精度
          weightDisplay = "${weight.toStringAsFixed(3)} $_currentUnit";
          // 触发语音播报
          _speakWeight(weight);
        });
      }
    } catch (e) {
      print('处理重量数据错误: $e');
    }
  }

  @override
  void dispose() {
    _speakTimer?.cancel(); // 清理语音播报定时器
    _stopWeightTimer();
    reader?.close();
    port?.close();
    _sendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SHINKO 电子天平秤'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 重量显示区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '重量显示',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (weightDisplay.isNotEmpty) {
                            Clipboard.setData(
                                    ClipboardData(text: weightDisplay))
                                .then((_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已复制: $weightDisplay'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            });
                          }
                        },
                        icon: Icon(Icons.copy, size: 18),
                        label: Text('复制'),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        weightDisplay.isEmpty ? '0.00 G' : weightDisplay,
                        style: TextStyle(
                          fontSize: 40,
                          fontFamily: 'Monospace',
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 32),

              // 操作按钮区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '操作控制',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sendCommand('T'),
                          icon: Icon(Icons.restart_alt, size: 20),
                          label: Text('归零'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.blue[700]!),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sendCommand('Z'),
                          icon: Icon(Icons.remove_circle_outline, size: 20),
                          label: Text('去皮'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.blue[700]!),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sendCommand('C'),
                          icon: Icon(Icons.settings_outlined, size: 20),
                          label: Text('去皮范围'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.blue[700]!),
                          ),
                        ),
                      ),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sendCommand('UNIT'),
                          icon: Icon(Icons.swap_horiz, size: 20),
                          label: Text('切换单位'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.blue[700]!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 32),

              // 连接设置区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '设备连接',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedPort,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.blue[700]!),
                      ),
                      labelText: '选择SHINKO天平秤',
                      hintText: '请选择SHINKO天平秤串口',
                      prefixIcon: Icon(Icons.scale),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    items: availablePorts.map((port) {
                      return DropdownMenuItem(
                        value: port,
                        child: Text('SHINKO天平秤 ($port)'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedPort = value;
                      });
                    },
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: port == null ? _connectToPort : null,
                          icon: Icon(Icons.link, size: 20),
                          label: Text('连接'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue[700],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: port != null ? _disconnectPort : null,
                          icon: Icon(Icons.link_off, size: 20),
                          label: Text('断开'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.red),
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
