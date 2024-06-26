# ❗ Maintainer Info

> [!IMPORTANT]  
> I've seen that the repo has been getting some attention lately.
> Unfortunately I don't have the time to do an update on Flutter 3 for null-safety as well.
> I would be happy if someone could do this. Gladly as a new maintainer or feel free to open a PR.

## Description

Flutter package which handles data packages to use with bluetooth low energy (BLE).
It splitts data into chunks based on the MTU size. So you don't need to worry about 
splitting and joining data packages on lower level. 

The package works in combination with the flutter_blue package, which is used for BLE communication

**Note**:
This package is still in work, so please be aware of breaking changes.

**Requirements for development**
To get started using this package to communicate with a raspberry Pi and Flutter, 

## Telegram

|                                  | File data mode (File sending)                                      | Message data mode (Command sending)                     |
|----------------------------------|--------------------------------------------------------------------|---------------------------------------------------------|
| Description                      | This mode is used for transfering binary files over ble.           | This mode is used for transfering string data over ble. |
| Indicator                        | \@F\@                                                             | \@S\@                                                    |
| transfer mode                    | binary                                                             | binary and retransformation                             |
| Header size - initial chunk      | 84 bytes                                                           | 7 bytes                                                 |
| Header size - following chunk(s) | 4 bytes                                                            | 2 bytes                                                 |
| Header data - initial chunk      | Indicator + total data size + sent chunk count + md5sum + filename | Indicator + total data size + sent chunk count + CRC8   |
| Header data - following chunk(s) | chunk index                                                        | chunk index + CRC8                                      |
| Usage data size                  | MTU - Header size = usage data                                     | MTU - Header size = usage data                          |
| Usage example                    | JSON Files, images, update files, ...                              | String commandos for sensors and actuators              |


**Support**:
- chunked data with "theoreticaly unlimited data size"
- Transfer of "Message" data and "Binary/File" data
- Cheksum calculation for messages and for files

**Communications way**:
* File data mode
  - Flutter --> powerIO-Box (stable)
  - Raspberry Pi --> Flutter (experimental)
  
* Message data mode
  - Flutter --> powerIO-Box (stable)
  - Raspberry Pi --> Flutter (stable)
  
**limitations**:
- filename size is limited to 41 bytes (enough for UUID v4)
- transfer rate (155 byte each package)
- Message data mode is limited to a maximum of 255 chunks

### visual telegram 

![Telegram view](doc/transmission_protocol.svg/)
