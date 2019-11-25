library telegram_constants;

/// Defines the initial marker of a string (command) message.
const STRING_TELEGRAM_PREFIX = "\$S\$";

/// Defines the end marker of a string (command) message.
const STRING_TELEGRAM_POSTFIX = "\$E\$";

/// Defines the initial marker of a file sending message.
const FILE_TELEGRAM_PREFIX = "\$F\$";

/// Defines the end marker of a file sending message.
const FILE_TELEGRAM_POSTFIX = "\$E\$";

/// The default data package size, used if none is defined.
const DEFAULT_TELEGRAM_MTU = 155;

/// The size of the header.
///
/// ```
/// $F$ + totalsize + chunkcount + md5sum + name = 3 + 4 + 4 + 32 + 41 = 83 bytes
/// ```
const HEADER_SIZE_FILES = 84;
const FILE_NAME_LENGTH = 41;

/// The size of the header.
///
/// ```
/// $S$ + totalsize + chunkcount + crc8 = 3 + 2 + 1 + 1 = 7 bytes
/// ```
const HEADER_SIZE_COMMANDS = 7;

/// The maximum time interval in seconds that can occur between data events.
const MAX_TIMEINTERVAL_BETWEEN_EVENTS = 3;