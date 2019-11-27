part of flutter_ble_data_handler;

const DEBUG = false;

/// A singleton that takes care of receiving data and dump them.
class DataReceiver {
  static final DataReceiver _singleton = DataReceiver._internal();

  var _lastReadingTs = 0;

  factory DataReceiver() {
    return _singleton;
  }

  DataReceiver._internal();

  Receiver _receiver;

  /// Adds and array of bytes [dataWithCheckBytes] to this handler.
  ///
  /// This takes care also to initialize the file when the
  /// header arrives and to dump once the datastream has
  /// reached its end.
  ///
  /// returns [true] if more data need to be retrieved, [false]
  /// if the file data have all arrived.
  bool onDataEvent(List<int> dataWithCheckBytes) {
    var currentTs = DateTime.now().millisecondsSinceEpoch;
    var deltaSeconds = (currentTs - _lastReadingTs) / 1000;
    _lastReadingTs = currentTs;
    if (_receiver == null ||
        deltaSeconds > TelegramConstants.MAX_TIMEINTERVAL_BETWEEN_EVENTS) {
      // if new, get the right receiver and initialize it with the first chunk
      _receiver = Receiver.getReceiver(dataWithCheckBytes);
      if (_receiver != null) {
        bool hasMoreData = _receiver.init(dataWithCheckBytes);
        if (!hasMoreData) {
          // done already, reset
          _receiver = null;
        }
      }
    } else {
      try {
        return _receiver.onDataEvent(dataWithCheckBytes);
      } catch (e) {
        _receiver = null;
        throw e;
      }
    }
    // if the event was not processed, stay open for others.
    return true;
  }

  /// Dump the current data list into a file.
  void dump() {
    print("dump was called");
    _receiver.dump();
    _receiver = null;
  }
}

/// An abstract class that handles incoming data.
abstract class Receiver {
  static Receiver getReceiver(List<int> bytesList) {
    if (bytesList.length < 3) {
      return null;
    }
    var string = String.fromCharCodes(bytesList.sublist(0, 3));
    if (string == TelegramConstants.STRING_TELEGRAM_PREFIX) {
      return CommandReceiver();
    } else if (string == TelegramConstants.FILE_TELEGRAM_PREFIX) {
      return FileReceiver();
    }
    return null;
  }

  /// Initialize the type of data receiver with the first chunk.
  ///
  /// returns [true] if more data need to be retrieved, [false]
  /// if all data arrived and the data where already [dump()]ed.
  bool init(List<int> bytesList);

  /// Triggered when an incoming data event occurrs.
  ///
  /// The event carries [bytesList] of data.
  ///
  /// returns [true] if more data need to be retrieved, [false]
  /// if all data arrived and the data are ready to be [dump()]ed.
  bool onDataEvent(List<int> bytesList);

  /// Dumps the retrieved data to the next processing chain.
  void dump();

}

/// A singleton that takes care of receiving command data.
class CommandReceiver implements Receiver {
  SplayTreeMap<int, List<int>> _bytesMap;
  int _chunkCount;
  int _runningChunkCount;
  int _totalLength;
  int _crc;
  String _lastDump;

  @override
  bool init(List<int> bytesList) {
    if (bytesList.length < TelegramConstants.HEADER_SIZE_COMMANDS) {
      throw ArgumentError(
          "The header of commands has to be of at least ${TelegramConstants.HEADER_SIZE_COMMANDS} bytes.");
    }
    if (DEBUG) {
      print("COMMAND HEADER EVENT: " +
          String.fromCharCodes(
              bytesList.sublist(TelegramConstants.HEADER_SIZE_COMMANDS)));
    }
    _bytesMap = new SplayTreeMap();
    _totalLength = ByteConversionUtilities.getInt16(bytesList.sublist(3, 5));
    _chunkCount = bytesList[5];
    _crc = bytesList[6];

    var dataBytes = bytesList.sublist(TelegramConstants.HEADER_SIZE_COMMANDS);
    _runningChunkCount = 0;
    _bytesMap[_runningChunkCount] = dataBytes;

    if (dataBytes.length >= _totalLength) {
      // >= because there might be padding
      //
      // command is shorter than an MTU, dump it directly.
      // ToDo: I changed this to the abstract class to pass a Callback function
      dump();
      return false;
    }
    return true;
  }

  @override
  bool onDataEvent(List<int> bytesList) {
    _runningChunkCount++;
    var chunkIndex = bytesList[0];
    var crc8 = bytesList[1]; // TODO handle that at some point

    if (chunkIndex > _chunkCount + 1) {
      print(
          "ERROR with last chunk of index $chunkIndex: ${String.fromCharCodes(bytesList)}");
      throw StateError("Something when wrong in the data stream.");
    }

    var dataBytes = bytesList.sublist(2);
    _bytesMap[chunkIndex] = dataBytes;

    if (_runningChunkCount < _chunkCount - 1) {
      return true;
    }
    return false;
  }

  @override
  void dump() {
    List<int> commandBytes = [];
    _bytesMap.values.forEach((bytesList) {
      commandBytes.addAll(bytesList);
    });

    String stringCommand = String.fromCharCodes(commandBytes).trim();

    if (stringCommand.length != _totalLength) {
      throw StateError(
          "ERROR: Recovered data differs from expected data size (${stringCommand.length} vs $_totalLength). Will not dump.");
    }

    // Kevin -> implement here command consuming
    UpdateHandler.instance.updateDumpedValue(stringCommand);
    _lastDump = stringCommand;
  }

}

/// A singleton that takes care of receiving file data.
class FileReceiver implements Receiver {
  static final FileReceiver _singleton = FileReceiver._internal();

  factory FileReceiver() {
    return _singleton;
  }

  FileReceiver._internal();

  SplayTreeMap<int, List<int>> _bytesMap;
  int _chunkCount;
  int _runningChunkCount;
  int _totalLength;
  String _md5;
  String _fileName;

  @override
  bool init(List<int> bytesList) {
    if (bytesList.length < TelegramConstants.HEADER_SIZE_FILES) {
      throw ArgumentError(
          "The header of files has to be of at least ${TelegramConstants.HEADER_SIZE_FILES} bytes.");
    }
    if (DEBUG) {
      print("FILE HEADER EVENT: " +
          String.fromCharCodes(
              bytesList.sublist(TelegramConstants.HEADER_SIZE_FILES)));
    }
    _bytesMap = new SplayTreeMap();
    _totalLength = ByteConversionUtilities.getInt32(bytesList.sublist(3, 7));
    _chunkCount = ByteConversionUtilities.getInt32(bytesList.sublist(7, 11));
    _md5 = String.fromCharCodes(bytesList.sublist(11, 43));
    _fileName = String.fromCharCodes(
        bytesList.sublist(43, TelegramConstants.HEADER_SIZE_FILES));
    _fileName = _fileName.trim();

    var dataBytes = bytesList.sublist(TelegramConstants.HEADER_SIZE_FILES);
    _runningChunkCount = 0;
    _bytesMap[_runningChunkCount] = dataBytes;

    if (dataBytes.length >= _totalLength) {
      // >= because there might be padding
      //
      // command is shorter than an MTU, dump it directly.
      dump();
      return false;
    }
    return true;
  }

  @override
  bool onDataEvent(List<int> bytesList) {
    _runningChunkCount++;
    var chunkIndex = ByteConversionUtilities.getInt32(bytesList.sublist(0, 4));
    if (chunkIndex > _chunkCount + 1) {
      print(
          "ERROR with last chunk of index $chunkIndex: ${String.fromCharCodes(bytesList)}");
      throw StateError("Something when wrong in the data stream.");
    }

    var dataBytes = bytesList.sublist(4);
    _bytesMap[chunkIndex] = dataBytes;

    if (_runningChunkCount < _chunkCount - 1) {
      return true;
    }
    return false;
  }

  @override

  /// Dump the current data list into a file.
  void dump() {
    List<int> fileBytes = [];
    _bytesMap.values.forEach((bytesList) {
      fileBytes.addAll(bytesList);
    });

    var fileBytesNoPadding = fileBytes.sublist(0, _totalLength);
    String md5hash = md5.convert(fileBytesNoPadding).toString();

    if (md5hash != _md5) {
      print(
          "ERROR: The checksum of the file doesn't equal the one declared in the package. Will not dump to file.");
      return;
    }

    // ToDo: Here substitute your file handling.
    String filePath = TestData.TEST_BASEPATH + _fileName;
    String writtenPath =
        ByteConversionUtilities.bytesToFile(filePath, fileBytesNoPadding);
    print("DUMPED DATA TO: " + writtenPath);
  }
}

/// Exception to identify sending of simultaneous messages.
class SingleSendingException implements Exception {
  String toString() =>
      "SingleSendingException: an attempt was made to send a message while the queue il locked.";
}

/// Class that handles sending of data through a bluetooth connection (via its characteristics).
class DataSender {
  DataSender._();

  static DataSender _instance = new DataSender._();

  static DataSender get instance => _instance;

  /// Variable to make sure sendings do not overlap.
  bool _isSending = false;

  static const mtuErrorMsg =
      "The MTU can't be smaller than the header size. The header need to be sent in a sigle message.";

  /// Send a file defined by the [filePath] through a given [bluetoothCharacteristic].
  ///
  /// Optionally the [mtu] can be forced, which has to be smaller than the [HEADER_SIZE].
  /// If [mtu] is not supplied the default of [DEFAULT_TELEGRAM_MTU] is be used.
  ///
  /// Optional callbacks are:
  ///
  /// * sendingCallback: a function that takes a bool.
  /// * chunkCountCallback: a function that takes an int of the current processed chunk.
  /// * totalCountCallback: a function that takes an int of the total chunk count.
  ///
  /// Throws a [SingleSendingException] if a sending is already ongoing.
  /// Throws [ArgumentError] if the supplied [mtu] is smaller than the [HEADER_SIZE].
  Future<void> sendFile(dynamic bluetoothCharacteristic, String filePath,
      {mtu = TelegramConstants.DEFAULT_TELEGRAM_MTU,
      sendingCallback,
      chunkCountCallback,
      totalCountCallback}) async {
    if (_isSending) {
      throw SingleSendingException();
    }
    _isSending = true;

    try {
      if (mtu < TelegramConstants.HEADER_SIZE_FILES) {
        throw ArgumentError(mtuErrorMsg);
      }
      filePath = filePath ??= TestData.path;
      String fileName = basename(filePath);

      Uint8List fileBytes = ByteConversionUtilities.bytesFromFile(filePath);

      String md5hash = md5.convert(fileBytes).toString();

      List<int> specs = TelegramConstants.FILE_TELEGRAM_PREFIX.codeUnits;

      // totalsize
      var fileBytesLength = fileBytes.length;
      List<int> totalSizeBytes =
          ByteConversionUtilities.bytesFromInt32(fileBytesLength);

      // chunks
      if (DEBUG) print("Used MTU = $mtu");
      int chunkMaxDataSize =
          mtu - 4; // chunk size minus the chunk index, a 32bit integer.

      // calculate chunk counts, considering that the first has no index, but any other chunk does
      // hence [chunkMaxDataSize] is used.
      int chunkCount = 1;
      int runningSize = mtu;
      while (
          runningSize < fileBytesLength + TelegramConstants.HEADER_SIZE_FILES) {
        runningSize += chunkMaxDataSize;
        chunkCount++;
      }

      if (totalCountCallback != null) totalCountCallback(chunkCount);

      List<int> chunkCountBytes =
          ByteConversionUtilities.bytesFromInt32(chunkCount);

      List<int> nameBytes = ByteConversionUtilities.nameToBytes(fileName);

      List<int> headerBytes = []
        ..addAll(specs) //
        ..addAll(totalSizeBytes) //
        ..addAll(chunkCountBytes) //
        ..addAll(md5hash.codeUnits) //
        ..addAll(nameBytes);

      int addToHeaderSize = mtu - headerBytes.length;
      int addToHeaderSizeSafe = math.min(addToHeaderSize, fileBytesLength);

      // send fist one with header
      var sublist = fileBytes.sublist(0, addToHeaderSizeSafe);
      List<int> chunk1Bytes = []..addAll(headerBytes)..addAll(sublist);
      ByteConversionUtilities.addPadding(chunk1Bytes, mtu);
      await bluetoothCharacteristic.write(chunk1Bytes, withoutResponse: false);

      int runningListIndex = addToHeaderSizeSafe;
      int runningChunkIndex = 1;
      while (runningChunkIndex < chunkCount) {
        List<int> indexBytes =
            ByteConversionUtilities.bytesFromInt32(runningChunkIndex);
        var from = runningListIndex;
        var to = runningListIndex + chunkMaxDataSize;
        if (to > fileBytesLength) {
          to = fileBytesLength;
        }
        var sublist = fileBytes.sublist(from, to);
        runningListIndex = runningListIndex + chunkMaxDataSize;

        List<int> chunkBytes = []..addAll(indexBytes)..addAll(sublist);
        ByteConversionUtilities.addPadding(chunkBytes, mtu);

        await bluetoothCharacteristic.write(chunkBytes, withoutResponse: false);
        print("Current chunk $runningChunkIndex of ${chunkCount - 1}");
        if (sendingCallback != null) sendingCallback(true);
        if (chunkCountCallback != null) chunkCountCallback(runningChunkIndex);

        runningChunkIndex++;
      }

      print("Send FILE process finished.");
      if (sendingCallback != null) sendingCallback(false);
    } finally {
      _isSending = false;
    }
  }

  /// Send a string [command] through a given [bluetoothCharacteristic].
  ///
  /// Optionally the [mtu] can be forced, which has to be smaller than the [HEADER_SIZE].
  /// If [mtu] is not supplied the default of [DEFAULT_TELEGRAM_MTU] is be used.
  ///
  /// Optional callbacks are:
  ///
  /// * sendingCallback: a function that takes a bool.
  /// * chunkCountCallback: a function that takes an int of the current processed chunk.
  /// * totalCountCallback: a function that takes an int of the total chunk count.
  ///
  /// Throws a [SingleSendingException] if a sending is already ongoing.
  /// Throws [ArgumentError] if the supplied [mtu] is smaller than the [HEADER_SIZE].
  Future<void> sendCommand(dynamic bluetoothCharacteristic, String command,
      {mtu = TelegramConstants.DEFAULT_TELEGRAM_MTU,
      sendingCallback,
      chunkCountCallback,
      totalCountCallback}) async {
    if (_isSending) {
      throw SingleSendingException();
    }
    _isSending = true;
    try {
      if (mtu < TelegramConstants.HEADER_SIZE_COMMANDS) {
        throw ArgumentError(mtuErrorMsg);
      }

      command = command ??= TestData.COMMAND_411BYTES;

      List<int> specs = TelegramConstants.STRING_TELEGRAM_PREFIX.codeUnits;

      // totalsize, 16 bits is enough
      var commandBytesLength = command.length;
      List<int> totalSizeBytes16 =
          ByteConversionUtilities.bytesFromInt16(commandBytesLength);

      if (DEBUG) print("Used MTU = $mtu");
      int chunkMaxDataSize = mtu -
          3; // chunk size minus the chunk index (an 8 bit integer) adn the crc8.

      // calculate chunk counts, considering that the first has no index, but any other chunk does
      // hence [chunkMaxDataSize] is used.
      int chunkCount = 1;
      int runningSize = mtu;
      while (runningSize <
          commandBytesLength + TelegramConstants.HEADER_SIZE_COMMANDS) {
        runningSize += chunkMaxDataSize;
        chunkCount++;
      }

      if (chunkCount > 255) {
        if (totalCountCallback != null) totalCountCallback(chunkCount);
        throw ArgumentError(
            "The length of the command and the choice of the MTU are not allowed to produce more than 255 chunk.");
      }

      List<int> headerBytes = []
        ..addAll(specs) //
        ..addAll(totalSizeBytes16) //
        ..add(chunkCount);
      // crc8 is still missing, will be added later, when the added data size is known
      int addToHeaderSize = mtu - (headerBytes.length + 1); // 1 for crc8
      int addToHeaderSizeSafe = math.min(addToHeaderSize, commandBytesLength);

      List<int> commandBytes = command.codeUnits;
      // send fist one with header
      //
      // First chunk will be: 3 bytes $S$ + 2 bytes totalsize + 1 int chunkCount + 1 int crc8 + data piece that fits
      var sublist = commandBytes.sublist(0, addToHeaderSizeSafe);
      int crc8 = Crc8Atm().convert(sublist);
      List<int> chunk1Bytes = []
        ..addAll(headerBytes)
        ..add(crc8)
        ..addAll(sublist);
      ByteConversionUtilities.addPadding(chunk1Bytes, mtu);
      await bluetoothCharacteristic.write(chunk1Bytes, withoutResponse: false);

      int runningListIndex = addToHeaderSizeSafe;
      int runningChunkIndex = 1;
      while (runningChunkIndex < chunkCount) {
        var from = runningListIndex;
        var to = runningListIndex + chunkMaxDataSize;
        if (to > commandBytesLength) {
          to = commandBytesLength;
        }
        var sublist = commandBytes.sublist(from, to);
        runningListIndex = runningListIndex + chunkMaxDataSize;

        int crc8 = Crc8Atm().convert(sublist);

//        CRC8 tmp = CRC8();
//        tmp.setList(sublist);
//        var value = tmp.getValue();

        List<int> chunkBytes = []
          ..add(runningChunkIndex)
          ..add(crc8)
          ..addAll(sublist);
        ByteConversionUtilities.addPadding(chunkBytes, mtu);

        await bluetoothCharacteristic.write(chunkBytes, withoutResponse: false);
        //print("Sent chunk: $runningChunkIndex");
        print("Current chunk $runningChunkIndex of ${chunkCount - 1}");
        if (sendingCallback != null) sendingCallback(true);
        if (chunkCountCallback != null) chunkCountCallback(runningChunkIndex);

        runningChunkIndex++;
      }

      print("Send COMMAND process finished.");
      if (sendingCallback != null) sendingCallback(false);
    } finally {
      _isSending = false;
    }
  }
}

/// Class to help with testing.
class TestData {
  static const TEST_BASEPATH = "/storage/emulated/0/";
  static const TEST_BASEPATH_SEND = "/storage/emulated/0/ble/";

  static const name = "test.json";

//  static const name = "error_generated.json";
//  static const name = "image.jpg";

  static const path = TEST_BASEPATH_SEND + name;

  static const COMMAND_31BYTES = "\$S\$1\$2\$4\$2019-11-14 10:09:52\$E\$";
  static const COMMAND_182BYTES =
      "\$S\$1\$2\$4\$AAAAAAAAAABBBBBBBBBBCCCCCCCCCCDDDDDDDDDDEEEEEEEEEEFFFFFFFFFFGGGGGGGGGGHHHHHHHHHHIIIIIIIIIIJJJJJJJJJJKKKKKKKKKKLLLLLLLLLLMMMMMMMMMMNNNNNNNNNNOOOOOOOOOOPPPPPPPPPPQQQQQQQQQQ\$E\$";
  static const COMMAND_411BYTES =
      "\$S\$1\$2\$4\$AAAAAAAAAA-AAAAAAAAAABBBBBBBBBB-BBBBBBBBBBCCCCCCCCCC-CCCCCCCCCCDDDDDDDDDD-DDDDDDDDDDEEEEEEEEEE-EEEEEEEEEEFFFFFFFFFF-FFFFFFFFFFGGGGGGGGGG-GGGGGGGGGGHHHHHHHHHH-HHHHHHHHHHIIIIIIIIII-IIIIIIIIIIJJJJJJJJJJ-JJJJJJJJJJKKKKKKKKKK-KKKKKKKKKKLLLLLLLLLL-LLLLLLLLLLMMMMMMMMMM-MMMMMMMMMMNNNNNNNNNN-NNNNNNNNNNOOOOOOOOOO-OOOOOOOOOOPPPPPPPPPP-PPPPPPPPPPQQQQQQQQQQ-QQQQQQQQQQRRRRRRRRRR-RRRRRRRRRRSSSSSSSSSS-SSSSSSSSSS\$E\$";
}

/// Class to help with updating streams. (Singletone)
class UpdateHandler {
  UpdateHandler._();

  static UpdateHandler _instance = new UpdateHandler._();
  static UpdateHandler get instance => _instance;

  BehaviorSubject<String> _dumpedValue = BehaviorSubject.seeded("");
  BehaviorSubject<int> _chunkCount = BehaviorSubject.seeded(0);
  BehaviorSubject<bool> _isSending = BehaviorSubject.seeded(false);
  int _totalChunkCount = 0;
  String _lastDumpedValue;

  /// The stream is updated if a Message data is completly dumped
  Stream<String> get dumpedValue => _dumpedValue.stream;

  /// Returns the last dumped value
  String get lastDumpedValue => _lastDumpedValue;

  /// The stream returns the current state of the send process
  Stream<bool> get isSending => _isSending.stream;

  /// The stream returns the current chunk if there is a send process
  Stream<int> get chunkCount => _chunkCount.stream;

  /// The value returns the total count of chunks
  int get totalChunkCount => _totalChunkCount;

  sendingCallback(bool value) {
    _isSending.add(value);
  }

  chunkCountCallback(int value) {
    _chunkCount.add(value);
  }

  totalCountCallback(int value) {
    _totalChunkCount = value;
  }

  updateDumpedValue(String value) {
    _dumpedValue.add(value);
    _lastDumpedValue = value;
  }
}
