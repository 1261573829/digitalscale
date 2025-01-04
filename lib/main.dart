import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  @override
  void initState() {
    super.initState();
    _getAvailablePorts();
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
    _timer = Timer.periodic(Duration(milliseconds: 500), (timer) {
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
            print('命令执行成功');
            _buffer = _buffer.replaceAll('A00', '');
          }

          // 处理重量数据
          if (_buffer.contains('G S')) {
            try {
              // 查找最后一个完整的数据包
              final pattern = RegExp(r'\+\d+\.\d+\s+G\s+S');
              final matches = pattern.allMatches(_buffer);

              if (matches.isNotEmpty) {
                // 获取最后一个匹配的数据
                final lastMatch = matches.last;
                final completeData = lastMatch.group(0)!;

                setState(() {
                  weightDisplay = completeData;
                });
                print('接收到重量数据: $completeData');

                // 清除已处理的数据，只保留最后一个匹配之后的数据
                _buffer = _buffer.substring(lastMatch.end);
              }
            } catch (e) {
              print('数据处理错误: $e');
            }
          }
        },
        onError: (error) {
          print('读取数据时出错: $error');
          _showMessage('数据读取错误');
        },
        onDone: () {
          print('数据流已关闭');
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

  @override
  void dispose() {
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
        title: Text('电子秤'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '重量',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SelectableText(
                                weightDisplay.isEmpty
                                    ? '0.00 G'
                                    : weightDisplay,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontFamily: 'Monospace',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (weightDisplay.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已复制: $weightDisplay')),
                              );
                            }
                          },
                          child: Text('复制'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sendCommand('T'),
                      child: Text('归零'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sendCommand('Z'),
                      child: Text('去皮'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sendCommand('C'),
                      child: Text('去皮范围'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedPort,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '选择串口设备',
                        prefixIcon: Icon(Icons.usb),
                      ),
                      items: availablePorts.map((port) {
                        return DropdownMenuItem(
                          value: port,
                          child: Text(port),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedPort = value;
                        });
                      },
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: port == null ? _connectToPort : null,
                            child: Text('连接'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: port != null ? _disconnectPort : null,
                            child: Text('断开'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
