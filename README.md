# CS:GO Essentials Plugin (1.5.0)
A comprehensive server management plugin for Counter-Strike: Global Offensive.

## Features
  * Block Fake-Duck
  * Force Lag Compensation 0 (aka disable AX)
  * Block untrusted angles
  * Block roll angles
  * Block Lag Peek
  * Detect and prevent air stuck exploits
  * Normalize angles
  * Latency management

## ConVar Configuration
```sourcepawn
sm_essentials_fd 0                  // Block fake duck
sm_essentials_ax 1                  // Move to spectators and force lagcomp
sm_essentials_unstrusted_angles 1   // Block untrusted angles
sm_essentials_roll 1                // Block roll angles
sm_essentials_lag_peek 1            // Block lag peek
sm_essentials_airstuck 1            // Block air stuck
sm_essentials_normalize_angles 1    // Normalize angles
sm_essentials_max_latency 200       // Maximum allowed latency (ms)
```

## Requirements
* SourceMod 1.11 or higher
* Counter-Strike: Global Offensive

## Installation
1. Ensure SourceMod is installed
2. Copy the plugin to `addons/sourcemod/plugins/`
3. Restart the server or reload plugins

## Notes
* Plugin version: 1.5.0
* Authors: dragos112 & unknowncheats & other developers
