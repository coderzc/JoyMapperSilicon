# JoyMapperPlus
Nintendo Joy-Con / Pro Controller mapper for Apple Silicon Macs. It maps gamepad buttons to keyboard and mouse events smoothly, and this fork focuses on making reconnects and day-to-day controller usage more reliable.

## Demo

[Switch手柄写代码，躺着 Vibe Coding](https://www.bilibili.com/video/BV1sMS9BnE2w)

## Advantages over alternatives

JoyMapperPlus keeps the original Apple Silicon gamepad mapping strengths, while improving the parts that matter during real use: reconnect behavior, mapping recovery after reconnect, safer rescanning, and modifier-only mappings such as Control-only.

|                                                          | Apple silicon native | Mouse working in games | 360° mouse move & acceleration | Both Joy Cons as a pair | Reliable reconnects | Mappings stay active after reconnect | Modifier-only mappings |
| :------------------------------------------------------: | :------------------: | :--------------------: | :----------------------------: | :---------------------: | :-----------------: | :----------------------------------: | :--------------------: |
|     [Enjoyable](https://yukkurigames.com/enjoyable/)     |          ❌           |           ✅            |               ❌                |            ❌            |          -          |                  -                   |           ❌           |
|       [Enjoy2](https://github.com/fyhuang/enjoy2/)       |          ❌           |           -            |               -                |            -            |          -          |                  -                   |           -            |
| [JoyKeyMapper](https://github.com/magicien/JoyKeyMapper) |          ❌           |           ❌            |               ✅                |            ✅            |          ❌         |                  ❌                  |           ❌           |
| [JoyMapperSilicon (original)](https://github.com/qibinc/JoyMapperSilicon) |          ✅           |           ✅            |               ✅                |            ✅            |          ❌         |                  ❌                  |           ❌           |
|                JoyMapperPlus (this build)                |          ✅           |           ✅            |               ✅                |            ✅            |          ✅         |                  ✅                  |           ✅           |

## Installation

1. Download the latest build from [Releases](https://github.com/coderzc/JoyMapperPlus/releases/)

2. Copy `JoyMapperPlus.app` to the `Applications/` folder.

## Usage

![screenshot](https://github.com/coderzc/JoyMapperPlus/blob/master/resources/screenshot/screenshot_1.png)

See [magicien's How to Use](https://github.com/magicien/JoyKeyMapper#how-to-use).

## Support the work

[![Paypal Donate](https://img.shields.io/badge/paypal-donate-orange)](https://paypal.me/joysilicon) You can buy me a cup of bubble tea if you like it.

## Acknowledgement

This application is heavily based on [magicien/JoyKeyMapper](https://github.com/magicien/JoyKeyMapper). We thank them a lot for open-sourcing the [JoyKeyMapper](https://apps.apple.com/us/app/joykeymapper/id1511416593?mt=12) app. Please also support them if possible.
