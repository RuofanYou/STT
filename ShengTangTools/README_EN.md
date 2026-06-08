# ShengTang Tools - STN Timeline Voice for World of Warcraft

## Overview

ShengTang Tools is a World of Warcraft addon that turns your self-authored tactical board (STN) timeline into clear Text‑to‑Speech callouts and simple countdown bars. It focuses on 12.0‑safe features: UI presentation, editable timelines, and local TTS playback — no combat log parsing, no automation.

## Core Features

### 🎯 Smart Voice Announcements
- **Automatic TTS Integration**: Leverages WoW's built-in Text-to-Speech engine to read timeline events
- **Intelligent Filtering**: Only announces events relevant to you, reducing audio spam
- **Precise Timing**: Syncs perfectly with combat timers for accurate callouts

### 👥 Advanced Player Recognition
- **Personal Events**: Highlights and announces events with your character name
- **Class-Specific Callouts**: Recognizes class-based assignments (e.g., {Mage}, {Priest})
- **Role-Based Filtering**: Supports role markers like {Healer}, {Tank}, {DPS}
- **Position Awareness**: Handles position-based calls ({Melee}, {Ranged})
- **Group Assignments**: Recognizes party/group markers ({Group1}, {Group2}, etc.)
- **Universal Calls**: Supports {Everyone} tags for raid-wide events

### 🎮 User Interface
- **Intuitive GUI**: Clean, professional interface matching WoW's aesthetic
- **Quick Access**: Simple `/st` command opens the configuration panel
- **Real-Time Testing**: Test button for immediate voice preview
- **Visual Feedback**: Status indicators for all active filters and settings
- **TTS Voice Selection**: Choose from available system voices
- **Voice Pack System**: Supports voice packs as standalone addons (TOC + mp3, zero code). STT auto-discovers installed packs — switch between them in settings. Ships with a default pack for common healing CDs.
- **Debug Mode**: Built-in debugging for troubleshooting

### 📊 Data Source
- **Dual Source**: Supports both the built‑in ShengTang tactical board (STN) and MRT notes through a shared parser / scheduler pipeline.
- **Single Runtime Path**: MRT and STN only differ at the source reader layer; filtering, scheduling, semantic templates, and TTS stay unified.

### ⚔️ Combat Integration
- **Auto-Start**: Starts on ENCOUNTER_START (raid only by default)
- **Dev Mode**: Optional — start/stop on any combat for local testing
- **Performance**: Lightweight, no CLEU listeners

## Installation

1. Download the ShengTang Tools folder
2. Place it in your WoW AddOns directory:
   - Windows: `C:\Program Files\World of Warcraft\_retail_\Interface\AddOns\`
   - Mac: `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or type `/reload` if already in-game

## Quick Start Guide

### Basic Setup
1. Type `/st` to open the configuration panel
2. Click "Test STN Voice" to verify TTS
3. Select your preferred TTS voice from the dropdown
4. Configure filters based on your preferences

### Filter Options
- **Only Announce Personal**: Only hear events with your name
- **Class-Related**: Include class-specific assignments
- **Role-Related**: Include tank/healer/DPS calls
- **Position-Related**: Include melee/ranged positioning
- **Everyone Tags**: Include raid-wide announcements
- **Group-Related**: Include your group's assignments

### Commands
- `/st` - Open main interface
- `/st test` - Test STN announcements
- `/st dev on|off` - Toggle developer mode (start on any combat)
- `/st filter` - Show current filter status
- `/st config` - Display configuration
- `/st debug` - Toggle debug mode
- `/st source` - Check current data source
  

## Advanced Features

### Timeline Format
Structured STN template with explicit time marks:
```
[方案]
名称 = Example Raid Plan
作者 = RaidLead

[人员]
Tank1 = Rofan
Healer1 = HealerOne

[时间轴]
{time:00:10} {{Tank1}} Tank swap
{time:00:25} {{Healer1}} Move to marker
{time:00:40} {Everyone} Stack for soak
{time:01:00} {Healers} Raid damage incoming
```

Notes
- STN accepts structured templates only: `[方案]`, `[人员]`, and exactly one of `[时间轴]` / `[触发轴]`.
- 12.0 removes combat‑log driven conditions; only time‑driven events are supported on the timeline path.

### Voice Customization
- Multiple TTS voice options
- Adjustable speech rate (through WoW settings)
- Language support based on game client

## Compatibility

- **WoW Version**: 12.0 Midnight or later
- **Dependencies**: none (optional dropdown library only)
