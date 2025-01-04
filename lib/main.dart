import 'package:flutter/material.dart';
import 'serial_communication.dart';
  import 'dart:ffi';
void main() {
  DynamicLibrary.open('/opt/homebrew/Cellar/libserialport/0.1.2/lib/libserialport.0.1.1.dylib');
      
  runApp(const MaterialApp(home: SerialDemo()));
}

class SerialDemo extends StatefulWidget {
  const SerialDemo({super.key});

  @override
  _SerialDemoState createState() => _SerialDemoState();
}

class _SerialDemoState extends State<SerialDemo> {
  final SerialCommunication _serial = SerialCommunication();
  final TextEditingController _sendController = TextEditingController();
  String _receivedData = '';
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _getAvailablePorts();
    Future.delayed(const Duration(seconds: 2), () {
      _getAvailablePorts();
    });
  }

  void _getAvailablePorts() {
    try {
      final ports = _serial.getAvailablePorts();
      setState(() {
        _availablePorts = ports;
        if (!ports.contains(_selectedPort)) {
          _selectedPort = ports.isNotEmpty ? ports.first : null;
        }
      });
    } catch (e) {
      print('获取串口列表错误: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取串口列表失败')),
      );
    }
  }

  Future<void> _initSerial() async {
    if (_selectedPort != null) {
      bool success = await _serial.initPort(_selectedPort!);
      if (success) {
        setState(() {
          _isConnected = true;
        });
        _serial.dataStream.listen((data) {
          setState(() {
            _receivedData += data;
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('串口连接成功')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('串口连接失败')),
        );
      }
    }
  }

  void _sendData() {
    if (_sendController.text.isNotEmpty) {
      _serial.sendData('${_sendController.text}\n');
    }
  }

  void _clearReceived() {
    setState(() {
      _receivedData = '';
    });
  }

  @override
  void dispose() {
    _sendController.dispose();
    _serial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RS-232C 串口通信'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getAvailablePorts,
            tooltip: '刷新设备列表',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: DropdownButtonFormField<String>(
                value: _selectedPort,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '选择串口设备',
                  prefixIcon: Icon(Icons.usb),
                ),
                hint: const Text('请选择串口'),
                items: _availablePorts.map((port) {
                  return DropdownMenuItem(
                    value: port,
                    child: Text(port),
                  );
                }).toList(),
                onChanged: _isConnected
                    ? null
                    : (value) {
                        setState(() {
                          _selectedPort = value;
                        });
                      },
                isExpanded: true,
              ),
            ),
            const SizedBox(height: 16),
            if (_availablePorts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '未检测到串口设备，请插入设备后重试',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                  label: Text(_isConnected ? '断开连接' : '连接串口'),
                  onPressed: _selectedPort == null ? null : _initSerial,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('发送数据:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sendController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: '输入要发送的数据',
                            enabled: _isConnected,
                          ),
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          ElevatedButton(
                            onPressed: _isConnected ? _sendData : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                            ),
                            child: const Text('发送'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('接收数据:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(Icons.clear_all),
                        label: const Text('清空'),
                        onPressed: _clearReceived,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _receivedData,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
