import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:libserialport/libserialport.dart';

class SerialCommunication {
  SerialPort? _port;
  SerialPortReader? _reader;

  // 获取可用串口列表
  List<String> getAvailablePorts() {
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      print('获取串口列表错误: $e');
      return [];
    }
  }

  // 初始化串口
  Future<bool> initPort(String portName) async {
    try {
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        print('无法打开串口');
        return false;
      }

      // 配置串口参数
      _port!.config = SerialPortConfig()
        ..baudRate = 9600
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      // 创建读取器
      _reader = SerialPortReader(_port!);

      return true;
    } catch (e) {
      print('串口初始化错误: $e');
      return false;
    }
  }

  // 发送数据
  Future<bool> sendData(String data) async {
    try {
      if (_port != null && _port!.isOpen) {
        final bytes = Uint8List.fromList(data.codeUnits);
        final writer = _createSerialPortWriter(_port!);
        writer.write(bytes);
        return true;
      }
      return false;
    } catch (e) {
      print('发送数据错误: $e');
      return false;
    }
  }

  // 读取数据
  Stream<String> get dataStream {
    if (_reader != null) {
      return _reader!.stream.map((data) {
        return String.fromCharCodes(data);
      });
    }
    return const Stream.empty();
  }

  // 关闭串口
  void dispose() {
    _reader?.close();
    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    _port = null;
  }

  // 定义SerialPortWriter类
  SerialPortWriter _createSerialPortWriter(SerialPort port) {
    return SerialPortWriter(port);
  }
}

// 定义SerialPortWriter类
class SerialPortWriter {
  final SerialPort port;

  SerialPortWriter(this.port);

  void write(Uint8List data) {
    port.write(data);
  }
}
