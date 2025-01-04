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
  List<String> _availablePorts = [];
  String? _selectedPort;
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
  bool _isSpeakEnabled = true;

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

  // 修改播报重量的方法
  Future<void> _speakWeight(double weight) async {
    // 如果语音播报被禁用，直接返回
    if (!_isSpeakEnabled) {
      return;
    }

    // 检查是否需要播报
    if (!_shouldSpeak(weight)) {
      return;
    }

    // 当重量为0时播放提示语
    if (weight == 0) {
      await flutterTts.speak("请把你要称重的物品放入指定称重区域");
      _lastSpokenWeight = weight;
      _lastSpeakTime = DateTime.now();
      return;
    }

    // 构建播报文本（固定使用克作为单位）
    String text = "${weight.toStringAsFixed(3)}克";

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
      _availablePorts = _getUsbPorts();
      if (_availablePorts.isNotEmpty) {
        _selectedPort = _availablePorts.first;
      }
    });
    print('可用的USB串口设备: $_availablePorts');
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
    if (_selectedPort == null) {
      _showMessage('请选择一个串口设备');
      return;
    }

    try {
      port = SerialPort(_selectedPort!);

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
          print('收到原始数据: $response'); // 打印原始数据
          _buffer += response;

          // 处理命令响应
          if (_buffer.contains('A00')) {
            print('收到命令响应: A00');
            _buffer = _buffer.replaceAll('A00', '');
            print('清除A00后的缓冲区: $_buffer');
          }

          // 处理重量数据
          if (_buffer.contains('G S') ||
              _buffer.contains('CT S') ||
              _buffer.contains('TL S') ||
              _buffer.contains('MO') ||
              _buffer.contains('OT S')) {
            print('收到重量数据: $_buffer'); // 打印完整的重量数据

            // 更新单位
            if (_buffer.contains('CT S')) {
              _currentUnit = 'CT';
              print('当前单位: CT');
            } else if (_buffer.contains('TL S')) {
              _currentUnit = 'TL';
              print('当前单位: TL');
            } else if (_buffer.contains('MO')) {
              _currentUnit = 'MO';
              print('当前单位: MO');
            } else if (_buffer.contains('OT S')) {
              _currentUnit = 'OT';
              print('当前单位: OT');
            } else {
              _currentUnit = 'G';
              print('当前单位: G');
            }

            _processWeightData(_buffer);
            print('处理后的重量显示: $weightDisplay'); // 打印处理后的显示结果
            _buffer = ''; // 清空缓冲区
          }
        },
        onError: (error) {
          print('串口读取错误: $error');
          _showMessage('数据读取错误');
        },
      );

      _startWeightTimer();
      setState(() {
        weightDisplay = '连接成功';
      });
      _showMessage('串口已连接');
      flutterTts.speak('连接成功');
    } catch (e) {
      print('连接错误: $e');
      _showMessage('连接失败: ${e.toString()}');
      setState(() {
        weightDisplay = '连接失败';
      });
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
      weightDisplay = '未连接';
    });
    _showMessage('串口已断开');
    flutterTts.speak('连接已断开');
  }

  void _sendCommand(String command) {
    if (port == null || !port!.isOpen) {
      _showMessage('串口未打开，无法发送命令');
      return;
    }

    String formattedCommand;
    String speakText = '';

    switch (command) {
      case 'T':
        formattedCommand = 'T \r\n'; // 去皮命令
        speakText = '归零'; // 修正：T命令实际是归零
        break;
      case 'Z':
        formattedCommand = 'Z \r\n'; // 归零命令
        speakText = '去皮'; // 修正：Z命令实际是去皮
        break;
      case 'O8':
        formattedCommand = 'O8\r\n'; // 单次输出数据命令
        break;
      case 'TT':
        formattedCommand = 'TT\r\n'; // 去皮范围命令
        speakText = '设置去皮范围';
        break;
      default:
        formattedCommand = command + '\r\n';
        break;
    }

    final bytes = formattedCommand.codeUnits;
    port!.write(Uint8List.fromList(bytes));
    print('发送命令: $formattedCommand');

    // 执行语音播报
    if (speakText.isNotEmpty && _isSpeakEnabled) {
      flutterTts.speak(speakText);
    }
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

  // 修改数据处理方法
  void _processWeightData(String data) {
    try {
      // 匹配重量数值（包括正负号的数字）
      final pattern = RegExp(r'[+-]\d+\.\d+');
      final match = pattern.firstMatch(data);
      if (match != null) {
        String numberStr = match.group(0)!;
        double weight = double.parse(numberStr);

        // 根据单位更新显示和播报
        setState(() {
          String unit = 'G'; // 默认单位
          if (_buffer.contains('TL S')) {
            unit = 'TL';
          } else if (_buffer.contains('CT S')) {
            unit = 'CT';
          } else if (_buffer.contains('MO')) {
            unit = 'MO';
          } else if (_buffer.contains('OT S')) {
            unit = 'OT';
          }

          weightDisplay = "${weight.toStringAsFixed(3)} $unit";
          _speakWeightWithUnit(weight, unit);
        });
      }
    } catch (e) {
      print('处理重量数据错误: $e');
    }
  }

  // 修改带单位的播报方法
  Future<void> _speakWeightWithUnit(double weight, String unit) async {
    if (!_isSpeakEnabled) {
      return;
    }

    if (!_shouldSpeak(weight)) {
      return;
    }

    if (weight == 0) {
      await flutterTts.speak("请把你要称重的物品放入指定称重区域");
      _lastSpokenWeight = weight;
      _lastSpeakTime = DateTime.now();
      return;
    }

    // 根据单位选择播报文本
    String text;
    switch (unit) {
      case 'TL':
        text = "${weight.toStringAsFixed(3)}钱";
        break;
      case 'CT':
        text = "${weight.toStringAsFixed(3)}克拉";
        break;
      case 'MO':
        text = "${weight.toStringAsFixed(3)}毛";
        break;
      case 'OT':
        text = "${weight.toStringAsFixed(3)}盎司";
        break;
      default:
        text = "${weight.toStringAsFixed(3)}克";
    }

    await flutterTts.speak(text);
    _lastSpokenWeight = weight;
    _lastSpeakTime = DateTime.now();
  }

  // 添加切换语音开关的方法
  void _toggleSpeak() {
    setState(() {
      _isSpeakEnabled = !_isSpeakEnabled;
      if (_isSpeakEnabled) {
        flutterTts.speak('语音播报已开启');
      } else {
        flutterTts.speak('语音播报已关闭');
      }
    });
  }

  // 添加刷新设备列表的方法
  void _refreshDevices() {
    setState(() {
      _availablePorts = _getUsbPorts();
      // 如果当前选中的端口不在新的列表中，清除选择
      if (!_availablePorts.contains(_selectedPort)) {
        _selectedPort = null;
      }
    });

    // 添加刷新提示
    if (_availablePorts.isEmpty) {
      _showMessage('未检测到USB串口设备');
      if (_isSpeakEnabled) {
        flutterTts.speak('未检测到USB串口设备');
      }
    } else {
      _showMessage('已刷新USB设备列表');
    }
  }

  List<String> _getUsbPorts() {
    // 获取所有可用端口
    final allPorts = SerialPort.availablePorts;
    // 过滤出 FT232R 设备
    return allPorts.where((port) {
      try {
        final serialPort = SerialPort(port);
        final description = serialPort.description;
        final manufacturer = serialPort.manufacturer;
        final productName = serialPort.productName;

        // 关闭端口
        serialPort.close();

        // 打印设备信息用于调试
        print('检查端口 $port:');
        print('- 描述: $description');
        print('- 制造商: $manufacturer');
        print('- 产品名: $productName');

        // 检查是否为 FT232R 设备
        return (description?.toLowerCase().contains('ft232r') ?? false) ||
            (manufacturer?.toLowerCase().contains('ftdi') ?? false) ||
            (productName?.toLowerCase().contains('ft232r') ?? false);
      } catch (e) {
        print('检查端口 $port 时出错: $e');
        return false;
      }
    }).toList();
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
        actions: [
          // 添加语音开关按钮
          IconButton(
            icon: Icon(_isSpeakEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: _toggleSpeak,
            tooltip: _isSpeakEnabled ? '关闭语音' : '开启语音',
          ),
        ],
      ),
      body: Column(
        children: [
          // 重量显示区域
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        if (weightDisplay.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: weightDisplay))
                              .then((_) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已复制: $weightDisplay'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                            // 添加复制成功的语音播报
                            if (_isSpeakEnabled) {
                              flutterTts.speak('复制成功');
                            }
                          });
                        }
                      },
                      icon: Icon(Icons.copy, size: 18),
                      label: Text('复制'),
                    ),
                    SizedBox(width: 24),
                  ],
                ),
                Text(
                  weightDisplay.isEmpty ? '未连接' : weightDisplay,
                  style: TextStyle(
                    fontSize: 72,
                    fontFamily: 'Monospace',
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // 其他控制部分使用 Padding 包裹
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                onPressed: () => _sendCommand('Z'),
                                icon:
                                    Icon(Icons.remove_circle_outline, size: 20),
                                label: Text('零点'),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  side: BorderSide(color: Colors.blue[700]!),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _sendCommand('TT'),
                                icon: Icon(Icons.settings_outlined, size: 20),
                                label: Text('去皮范围'),
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
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedPort,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.blue[700]!),
                                  ),
                                  labelText: '选择SHINKO天平秤',
                                  hintText: '请选择SHINKO天平秤串口',
                                  prefixIcon: Icon(Icons.scale),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 16),
                                ),
                                items: _availablePorts.map((port) {
                                  return DropdownMenuItem(
                                    value: port,
                                    child: Text('SHINKO天平秤 ($port)'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedPort = value;
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                // 调用刷新设备列表的方法
                                _refreshDevices();
                              },
                            ),
                          ],
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
                                onPressed:
                                    port != null ? _disconnectPort : null,
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
          ),
        ],
      ),
    );
  }
}
